# Concepts Deep Dive — Interview Q&A Notes

> Things I understood through conversation, explained in plain language.
> Use this as a quick-recall reference before the interview.

---

## 1. Terraform State File — What It Is and Where It Lives

### The short answer

Terraform needs to know what already exists in AWS before it plans any changes.
It tracks this in a file called `terraform.tfstate`.

### Two files — do not confuse them

| File | What it is |
| --- | --- |
| `.terraform/terraform.tfstate` | Local metadata only. Just records "this project uses S3 as the backend". Always looks nearly empty. Ignore it. |
| `s3://octa-byte-terraform-state/prod/terraform.tfstate` | The REAL state file. Contains every VPC ID, ALB ARN, RDS endpoint, ECS service ARN — everything Terraform manages. |

### What the real state file looks like while infrastructure is running

```json
{
  "resources": [
    {
      "type": "aws_vpc",
      "instances": [{ "attributes": { "id": "vpc-07000c2f9d01c6cc4", "cidr_block": "10.0.0.0/16" } }]
    },
    {
      "type": "aws_lb",
      "instances": [{ "attributes": { "dns_name": "octa-byte-prod-alb-xxx.us-east-1.elb.amazonaws.com" } }]
    }
  ]
}
```

### What the state file looks like after terraform destroy

```json
{
  "resources": [],
  "outputs": {},
  "serial": 37
}
```

`"resources": []` = destroy was clean. Nothing left in AWS.

The `serial` field increments by 1 on every apply or destroy.
Serial 37 means this state file has been written 37 times total.

### Interview one-liner
>
> "The state file in S3 is the single source of truth for what Terraform
> manages in AWS. Every plan reads it, every apply updates it."

---

## 2. S3 State Locking — How It Actually Works

### The problem it solves

If two engineers or two CI/CD pipeline runs both run `terraform apply` at the
same time, both read the same state, both plan, both write back — the second
write silently overwrites the first. State corruption.

### The mechanism — S3 Conditional PUT

Every `terraform apply` does this before touching anything:

```
Step 1: Try to CREATE the lock file (conditionally)
PUT s3://octa-byte-terraform-state/prod/terraform.tfstate.tflock
Condition: "only write if this file does NOT already exist"

  File does not exist → S3 creates it → this apply gets the lock ✅
  File already exists → S3 rejects it → this apply is blocked  ❌
  Error: "Error acquiring the state lock — another process is running"
```

```
Step 2: Read state, plan, apply changes to AWS

Step 3: Delete the lock file when done
DELETE s3://octa-byte-terraform-state/prod/terraform.tfstate.tflock
Lock released. Next apply can now run.
```

### Why it is race-condition proof

The conditional PUT is an atomic S3 operation. Even if two requests arrive
at the exact same millisecond, S3 guarantees only one succeeds.

```
Engineer A  → PUT (if not exists) → S3 → SUCCESS (lock created)
Engineer B  → PUT (if not exists) → S3 → REJECTED (already exists)
```

### My understanding in one sentence
>
> Every terraform apply conditionally creates a .tflock file in S3.
> If the file exists, another apply is running and the new one is rejected.
> Once the apply finishes, the lock file is deleted so the next run can go.

---

## 3. The Stale Lock — Edge Case to Know

### What causes it

If `terraform apply` is killed mid-run (power cut, pipeline timeout, Ctrl+C)
BEFORE the delete step runs, the `.tflock` file stays in S3 forever.

### What you see next time

```
Error: Error acquiring the state lock
Lock Info:
  ID:   abc-123-def
  Who:  bindukumar@laptop
  Path: prod/terraform.tfstate.tflock
```

### The fix

```bash
terraform force-unlock abc-123-def
```

This just deletes the `.tflock` file from S3.

Only do this if you are 100% certain no other apply is actually running.
If you force-unlock while a real apply is in progress, you defeat the
entire point of locking and risk state corruption.

---

## 4. Old Way vs New Way — DynamoDB vs S3 Native Locking

| | DynamoDB (old, before Terraform 1.10) | S3 use_lockfile (new, Terraform 1.10+) |
| --- | --- | --- |
| How it works | Write a lock row to a DynamoDB table | Conditional PUT to S3 |
| Extra resource needed | Yes — a whole DynamoDB table to manage | No — uses the same S3 bucket |
| Cost | Near zero but still extra infra to provision | Zero extra cost |
| Most tutorials show | DynamoDB | DynamoDB (they are outdated) |

This project uses Terraform 1.15.8 (well past 1.10), so we explicitly
removed DynamoDB and use `use_lockfile = true`. Using DynamoDB here
would be cargo-culting a legacy pattern the ecosystem has moved past.

### Interview one-liner
>
> "DynamoDB locking was the only option before Terraform 1.10.
> From 1.10 onwards, S3 conditional writes handle it natively —
> no extra DynamoDB table needed. Our version is 1.15.8 so we use
> the native approach."

---

## 5. What Was Actually Deleted by terraform destroy

### Deleted (everything Terraform created)

- VPC, subnets, route tables, internet gateway, NAT gateway
- ALB, target groups, listener rules
- ECS cluster, frontend service, backend service (Fargate tasks)
- RDS PostgreSQL database
- ECR repositories (and all Docker images inside them)
- Security groups (ALB, ECS, RDS)
- IAM roles (GitHub Actions OIDC role and policies)
- CloudWatch log groups, alarms, dashboards
- SNS alerts topic
- Elastic IPs

### NOT deleted (intentionally)

| Resource | Why |
| --- | --- |
| S3 bucket `octa-byte-terraform-state` | Terraform never destroys its own backend — it would destroy the state mid-operation |
| Portfolio S3 buckets | Completely separate from this project, Terraform never managed them |
| CloudFront distributions | Same — outside Terraform scope |

### How to verify destroy was clean

Two checks:

1. S3 state file shows `"resources": []`
2. `aws resourcegroupstaggingapi get-resources` returns no Octa Byte tagged resources
Both confirmed — destroy was 100% clean.

### Billing after destroy

Paying zero for Octa Byte infrastructure.
The S3 state bucket costs less than $0.01/month for the ~10KB state file.

## 6. The `random` and `time` Providers

### What they do
* **`random`**: Used to generate random strings, integers, passwords, or IDs. (e.g., `random_password` generates a secure password, `random_string` generates a unique suffix for a bucket name).
* **`time`**: Used to interact with time. The most common use is `time_sleep` to add a deliberate pause (e.g., "wait 30 seconds after creating this IAM role before trying to use it so AWS has time to propagate it").

### Why they are in our `versions.tf`
You might notice we don't explicitly write `resource "random_password"` or `resource "time_sleep"` anywhere in our `main.tf`. So why are they pinned in `versions.tf`?

Because we use **Terraform Registry Modules** (like `terraform-aws-modules/vpc` and `terraform-aws-modules/rds`). These modules are built by the community and they *do* use these providers internally. 
* The RDS module uses `random` (a `random_id` for the final-snapshot identifier).
* The ECS module's cluster sub-module uses `time` (a `time_sleep` to let AWS settle). The VPC module uses neither.

When you use a module that depends on a provider, your project inherits that dependency. It is a Terraform best practice to explicitly pin the versions of *all* providers your code relies on — both direct and indirect — so a breaking change in the `random` provider doesn't suddenly break your RDS module deployment.

### Interview one-liner
> "Even though we don't call them directly, the community modules we use (like VPC and RDS) rely on the `random` and `time` providers internally. Pinning their versions in our root `versions.tf` ensures stable, reproducible deployments and prevents upstream breaking changes."

### What happens if we don't pin them in `versions.tf`?
If you delete the `random` and `time` blocks from `versions.tf`, **Terraform will still download them** when you run `terraform init`. It knows the RDS and ECS modules need them.

However, because you didn't specify a version, Terraform will grab the **latest available version** on the day you run `init`. 

This is dangerous in a production environment:
1. Your CI/CD pipeline runs on a fresh machine every time.
2. If HashiCorp releases `random v4.0` on a Friday with breaking changes, your pipeline will automatically download v4.0 on Monday and fail.
3. Your deployment breaks even though **you didn't change a single line of your own code**.

By pinning them with `version = ">= 3.1.0"` or `~> 3.0`, you guarantee that your CI/CD pipeline will only download safe, compatible versions, making your builds 100% reproducible.

## 7. Terraform Built-in Functions Used in the Code

During the interview, showing that you know *how* and *why* to use Terraform's built-in functions proves you are writing dynamic, reusable code (not just hardcoding values). 

We used three important functions in this project: `slice()`, `cidrsubnet()`, and `jsonencode()`.

### 1. `slice()`
**Where it is used:** `main.tf` (VPC configuration)
**The code:** `azs = slice(data.aws_availability_zones.available.names, 0, 2)`

**Syntax:** 
`slice(list, start_index, end_index)`
* `list`: The array of items you are pulling from.
* `start_index`: Where to start (inclusive, usually 0).
* `end_index`: Where to stop (exclusive).

**What to tell the interviewer:**
> "I used the `slice()` function to dynamically grab exactly two Availability Zones for the VPC. Instead of hardcoding `['us-east-1a', 'us-east-1b']`, I fetch the list of all healthy AZs in the current region using a data source, and then `slice(..., 0, 2)` takes the first two. This ensures the code is completely portable — if we deploy to `eu-west-1` tomorrow, it automatically grabs `eu-west-1a` and `eu-west-1b` without us changing any code."

### 2. `cidrsubnet()`
**Where it is used:** `main.tf` (VPC subnet CIDR blocks)
**The code:**
```hcl
public_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
private_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 2)]
database_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 4)]
```

**Syntax:**
`cidrsubnet(prefix, newbits, netnum)`
* `prefix`: the base CIDR block to carve up — here, `local.vpc_cidr` = `10.0.0.0/16`.
* `newbits`: how many bits to extend the prefix by. `8` turns a `/16` into a `/24` (65,536 IPs → 256 IPs per subnet).
* `netnum`: which `/24` block within that `/16` to return, zero-indexed.

`k` is the AZ's index from the `for k, v in local.azs` loop (`0`, `1`, ...). Each tier is offset by a block of 2, so with exactly 2 AZs the three tiers land on non-overlapping ranges — verified with `terraform console`:

| Tier | Expression | AZ0 | AZ1 |
|---|---|---|---|
| public  | `k + 0` | `10.0.0.0/24` | `10.0.1.0/24` |
| private | `k + 2` | `10.0.2.0/24` | `10.0.3.0/24` |
| database| `k + 4` | `10.0.4.0/24` | `10.0.5.0/24` |

**What to tell the interviewer:**
> "`cidrsubnet()` is what carves the single `/16` VPC CIDR into the `/24` subnets each tier needs, without me typing out six CIDR blocks by hand. The `newbits` argument of `8` takes a `/16` to a `/24`; `netnum` picks which one. I loop over the AZ index for the base subnet number and offset each tier by 2, so public, private, and database never land on the same block."

**Honest edge case to name if pushed:**
> "This offset scheme — `+0`, `+2`, `+4` — is only collision-free because the AZ count is hardcoded to exactly 2 via `slice(..., 0, 2)` earlier in the file. I actually tested this: if you bump that slice to 3 AZs without changing the offsets, public's third subnet (`k=2` → netnum 2 → `10.0.2.0/24`) collides with private's first subnet (`k=0+2` → netnum 2 → also `10.0.2.0/24`). The robust fix for a variable AZ count is offsetting each tier by a fixed ceiling — `k + max_azs`, `k + 2*max_azs` — instead of a literal `+2`/`+4`, so growing the AZ count can never walk into the next tier's range. I'd flag this as a known limitation rather than let the interviewer find it."

### 3. `jsonencode()`
**Where it is used:** `monitoring.tf` (CloudWatch Dashboards)
**The code:** 
```hcl
dashboard_body = jsonencode({
  widgets = [
    { type = "metric", x = 0, ... }
  ]
})
```

**Syntax:** 
`jsonencode(expression)`
* `expression`: A Terraform map (dictionary) or object that you want to convert into a JSON string.

**What to tell the interviewer:**
> "For the CloudWatch dashboards, the `dashboard_body` argument expects a raw JSON string. Instead of writing a massive, hard-to-read JSON block wrapped in an EOF heredoc, I used `jsonencode()`. This allows me to write the dashboard structure as native Terraform objects (HCL). The biggest benefit is that `jsonencode()` allows me to inject Terraform variables and resource attributes directly into the dashboard — like `module.alb.arn_suffix` — which is impossible if you just paste a raw JSON string."
