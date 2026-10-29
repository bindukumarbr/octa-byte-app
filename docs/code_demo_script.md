# Octa Byte — Code Demo Walkthrough Script

> **How to use this:** Open each file in VS Code before the interview.
> Go through them in the numbered order below. For each file, the
> "Say this" block is your spoken commentary. The "Point to" line tells
> you exactly which code to hover over or highlight on screen.
> The "Cross-Questions" are what interviewers ask after seeing that specific code.

---

## Demo Order (quick reference)

| # | File | What it proves |
|---|---|---|
| 1 | `terraform/environments/prod/backend.tf` | Remote state + native S3 locking |
| 2 | `terraform/environments/prod/versions.tf` | Pinned provider versions |
| 3 | `terraform/environments/prod/main.tf` | Entire infrastructure in one declarative file |
| 4 | `terraform/environments/prod/outputs.tf` | Terraform wiring to CI/CD |
| 5 | `.github/workflows/deploy.yml` | Full CI/CD pipeline |
| 6 | `backend/index.js` | Fail-fast schema init |
| 7 | `backend/__tests__/api.test.js` | Real unit tests |
| 8 | `backend/db.js` | SSL-enforced DB connection |

---

## FILE 1 — `terraform/environments/prod/backend.tf`

**Open this file first. It is only 8 lines — perfect opener.**

```hcl
terraform {
  backend "s3" {
    bucket       = "octa-byte-terraform-state"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
```

**Say this:**
> "The first thing I want to show is the Terraform backend configuration.
> The state file is stored remotely in an S3 bucket — this means any
> engineer on the team, or any CI/CD runner, reads from and writes to the
> same single source of truth. State is not on anyone's laptop.
>
> The important line here is `use_lockfile = true`. Most tutorials you will
> find online still use a separate DynamoDB table for state locking —
> that was the only option before Terraform 1.10. From 1.10 onwards,
> Terraform can lock the state file natively using S3's conditional write
> feature. I explicitly removed DynamoDB from this configuration because
> it is an unnecessary piece of infrastructure when your Terraform version
> supports native locking. This project is pinned to version 1.11+, which
> I will show you in the next file."

**Point to:** `use_lockfile = true` — pause on this line.

**Cross-Questions:**

> **"What happens if two pipeline runs start at exactly the same time?"**
> "The first run to write acquires the lock via an S3 conditional PUT. The
> second run sees the lock file exists and either waits or fails immediately
> depending on the `-lock-timeout` flag. Without locking, both runs would
> read the same state, plan against it, and write conflicting state files —
> corruption guaranteed."

> **"Why not store the state locally?"**
> "A local state file only exists on the machine that ran Terraform. Any
> teammate running `terraform plan` would be working against a different
> state, leading to configuration drift within minutes. Remote state is
> non-negotiable for any team-based workflow."

---

## FILE 2 — `terraform/environments/prod/versions.tf`

```hcl
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    ...
  }
}
```

**Say this:**
> "This file pins the minimum Terraform version and the AWS provider version.
> `required_version = '>= 1.11.0'` is what enables `use_lockfile` in
> the backend — I verified this before removing DynamoDB, not assumed it.
>
> The AWS provider is pinned to `~> 6.0`, which means any 6.x release but
> nothing that jumps to 7.0. This is a standard defensive pin — a major
> version bump can include breaking changes in resource arguments, and an
> unpinned provider would silently pull in a breaking version on the next
> `terraform init`."

**Point to:** `required_version` and `version = "~> 6.0"`.

**Cross-Questions:**

> **"What does the `~>` operator mean in Terraform?"**
> "It is the pessimistic constraint operator — it allows patch and minor
> version upgrades but not major version bumps. `~> 6.0` allows 6.1, 6.2,
> 6.99, but not 7.0. It is equivalent to `>= 6.0, < 7.0`."

---

## FILE 3 — `terraform/environments/prod/main.tf`

**This is the centrepiece. Walk through it in four logical blocks.**

### Block A — VPC Module (open file, scroll to the top)

**Say this:**
> "This single file provisions the entire AWS infrastructure. Let me walk
> through it in order. First, the VPC."

**Point to:**
```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  ...
  azs              = ["us-east-1a", "us-east-1b"]
  public_subnets   = [...]
  private_subnets  = [...]
  database_subnets = [...]
  ...
}
```

**Say this:**
> "The VPC module creates three tiers of subnets replicated across two
> Availability Zones. Notice there are three distinct subnet arrays:
> `public_subnets` for the ALB, `private_subnets` for the ECS tasks, and
> `database_subnets` for RDS. These map directly to the three security
> boundaries I described — the database subnet has no internet gateway route
> by design."

---

### Block B — ALB Path-Based Routing (scroll to the ALB module)

**Point to:**
```hcl
listeners = {
  http = {
    port     = 80
    protocol = "HTTP"
    forward = {
      target_group_key = "frontend"   # <-- default action
    }
    rules = {
      api = {
        priority = 10
        conditions = [{
          path_pattern = {
            values = ["/api/*"]        # <-- override for API traffic
          }
        }]
        actions = [{
          forward = {
            target_group_key = "backend"
          }
        }]
      }
    }
  }
}
```

**Say this:**
> "This is the ALB path-based routing. There is one listener on port 80.
> The default action forwards all traffic to the frontend target group.
> There is one override rule — priority 10 — that matches anything under
> `/api/*` and forwards it to the backend target group instead.
>
> This is how a single DNS name serves both the frontend React app and the
> Node.js API. The browser fetches the frontend from `/` and makes API
> calls to `/api/transaction` — both go to the same ALB hostname, the ALB
> routes them to the correct container."

---

### Block C — RDS with Managed Password (scroll to the db module)

**Point to:**
```hcl
module "db" {
  ...
  manage_master_user_password = true
  ...
}
```

**Say this:**
> "This single boolean is one of the most important security decisions in
> the entire project. `manage_master_user_password = true` tells Terraform
> to instruct AWS to generate the database password, store it in Secrets
> Manager, and handle rotation natively. I never set a password. It never
> appears in Terraform variables, in the state file, or in any config file."

---

### Block D — ECS Backend with Secrets Injection (scroll to ECS backend service)

**Point to these two blocks together:**
```hcl
task_exec_secret_arns = ["${module.db.db_instance_master_user_secret_arn}*"]

secrets = [
  {
    name      = "DB_PASSWORD"
    valueFrom = "${module.db.db_instance_master_user_secret_arn}:password::"
  }
]
```

**Say this:**
> "These two blocks wire the secret to the container. The first line grants
> the ECS Task Execution Role permission to call `secretsmanager:GetSecretValue`
> on this specific secret ARN — and only this secret. The real production
> bug I hit was exactly that this permission was missing: the container
> failed with `AccessDeniedException`. You'll also notice a trailing
> wildcard on the ARN. I added it while debugging, because Secrets Manager
> appends a random 6-character suffix to every secret ARN. Honestly, the
> module's output ARN already includes that suffix, so the wildcard is
> probably unnecessary. I kept it as a defensive precaution and haven't
> re-tested without it.
>
> The `secrets` block tells ECS to fetch the value of the `password` key
> from that secret and inject it into the container as the `DB_PASSWORD`
> environment variable. It goes directly into memory — it never touches disk."

**Cross-Questions:**

> **"Why is the wildcard on the ARN not a security risk?"**
> "Because the part before the wildcard is this one secret's full ARN,
> which includes the secret's unique name and AWS's random suffix. The `*`
> can only match ARNs that begin with that exact string, so no unrelated
> secret can match. And as I said, it's probably not even needed."

> **"What would happen if you removed `task_exec_secret_arns`?"**
> "The container would fail to start with `ResourceInitializationError:
> AccessDeniedException`. ECS would retry, fail health checks, and the
> rolling deployment would stall with the old version still serving traffic.
> That is exactly the error I hit and debugged early in this project."

---

### Block E — OIDC IAM Trust Policy (scroll to the bottom of main.tf)

**Point to:**
```hcl
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:bindukumarbr@121097989/octa-byte-app@1351143352:*"]
    }
  }
}
```

**Say this:**
> "This is the IAM trust policy for the GitHub Actions OIDC integration.
> The `sub` claim condition is what scopes the trust to my specific
> repository. Notice the format uses numeric IDs rather than the repository
> name string. GitHub migrated to this immutable claim format to prevent
> trust-policy hijacking — if a repository is deleted and recreated with
> the same name, the numeric ID changes, so the trust policy stops matching
> automatically.
>
> I discovered this after the initial OIDC setup kept failing. I decoded
> the actual JWT token from a failed pipeline run to see what sub claim
> GitHub was actually embedding, then updated this condition to match it."

**Cross-Questions:**

> **"Where are the AWS access keys stored in GitHub?"**
> "Nowhere. That is the entire point. The only AWS-related GitHub secret is
> `AWS_ACCOUNT_ID`, which is not a credential — it is just a number needed
> to construct the role ARN. No `AWS_ACCESS_KEY_ID`, no
> `AWS_SECRET_ACCESS_KEY`. The OIDC token is what authenticates each run.
> The one other secret in the workflow is `SLACK_WEBHOOK_URL`, used only by
> the failure-notification job — it can post to a Slack channel and nothing
> else, and it has no access to AWS."

---

## FILE 4 — `terraform/environments/prod/outputs.tf`

**Point to:**
```hcl
output "alb_dns_name" {
  value = module.alb.dns_name
}

output "ecr_frontend_repository_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "ecr_backend_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "db_secret_arn" {
  value     = module.db.db_instance_master_user_secret_arn
  sensitive = true
}
```

**Say this:**
> "Terraform outputs are how the infrastructure layer communicates its
> results to the outside world. After `terraform apply`, these values are
> printed to the terminal and stored in the state file.
>
> The `alb_dns_name` output gives you the live URL of the application.
> The `ecr_*_repository_url` outputs give the CI/CD pipeline the exact
> ECR registry URL to push Docker images to.
> The `db_secret_arn` is marked `sensitive = true` — Terraform will not
> print this value to the terminal or logs even if someone runs
> `terraform output`. You must explicitly request it with
> `terraform output -raw db_secret_arn`."

---

## FILE 5 — `.github/workflows/deploy.yml`

**Walk through this in three sections.**

### Section A — OIDC Authentication step

**Point to:**
```yaml
permissions:
  id-token: write
  contents: read

- name: Configure AWS credentials via OIDC
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-role
    aws-region: ${{ env.AWS_REGION }}
```

**Say this:**
> "The `permissions` block at the top is critical — `id-token: write`
> tells GitHub to generate an OIDC token for this workflow run. Without
> this, the JWT is never issued and the credential exchange cannot happen.
> The `configure-aws-credentials` action then exchanges that token for
> temporary AWS credentials that expire when the job ends."

---

### Section B — Image tagging + Trivy

**Point to:**
```yaml
- name: Set image tag from Git SHA
  id: meta
  run: echo "tag=${{ github.sha }}" >> $GITHUB_OUTPUT

- name: Scan backend image with Trivy
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: .../${{ steps.meta.outputs.tag }}
    format: table
    exit-code: 0
    severity: HIGH,CRITICAL
```

**Say this:**
> "The image tag is the Git commit SHA — not `latest`. This means every
> image in ECR is traceable back to an exact commit. Rollback is instant:
> find the previous ECS task definition revision, force a new deployment,
> done — no rebuild.
>
> After building the image, Trivy scans it for CVEs. It checks the entire
> container layer stack including the base OS packages, not just the Node.js
> dependencies. `exit-code: 0` means it reports findings but does not fail
> the build — in a mature setup you would change this to `1` for CRITICAL
> findings and add a documented waiver process for unpatched CVEs."

---

### Section C — ECS Rolling Deploy

**Point to:**
```yaml
- name: Download backend task definition
  run: |
    aws ecs describe-task-definition \
      --task-definition backend \
      --query taskDefinition > task-definition-backend.json

- name: Render new backend task definition
  uses: aws-actions/amazon-ecs-render-task-definition@v1
  with:
    task-definition: task-definition-backend.json
    container-name: backend
    image: ...${{ needs.build-and-push.outputs.image-tag }}

- name: Deploy backend to ECS
  uses: aws-actions/amazon-ecs-deploy-task-definition@v2
  with:
    task-definition: ${{ steps.render-backend.outputs.task-definition }}
    service: backend
    cluster: ${{ env.ECS_CLUSTER }}
    wait-for-service-stability: true
```

**Say this:**
> "The deployment pattern is three steps: describe, render, deploy.
> First, we download the current live task definition from AWS. Second,
> we use the official Amazon action to inject the new image URI into it —
> only the image field changes, everything else (environment variables,
> secrets, resource limits) stays exactly as Terraform defined it.
> Third, we register the new revision and tell ECS to update the service.
>
> `wait-for-service-stability: true` on the backend means the pipeline
> blocks until the new containers pass health checks and the old ones are
> drained. This is zero-downtime rolling deployment — there is always at
> least one healthy container serving traffic throughout the update."

**Cross-Questions:**

> **"What is the `needs` dependency between jobs?"**
> "The `deploy-production` job declares `needs: build-and-push`. This
> creates a sequential dependency chain — deploy cannot start until build
> succeeds. It also enables output sharing: `needs.build-and-push.outputs.image-tag`
> is how the deploy job gets the Git SHA that the build job generated."

> **"What does the production environment block do?"**
> "It maps the job to a GitHub Environment named `production`. GitHub
> Environments can have required reviewers — a human must click Approve
> in the GitHub UI before the deploy job starts. This is the manual
> approval gate that separates automated build from authorized release."

---

## FILE 6 — `backend/index.js`

**Scroll to the bottom of the file — the IIFE block.**

**Point to:**
```javascript
(async () => {
  try {
    const schemaSql = fs.readFileSync(
      path.join(__dirname, 'schema.sql'), 'utf8'
    );
    await pool.query(schemaSql);
    console.log('Database schema initialized');

    // Start server only AFTER schema is guaranteed to exist
    const server = app.listen(port, () => {
      console.log(`Backend listening on port ${port}`);
    });

    ...

  } catch (err) {
    console.error('CRITICAL: Failed to initialize database schema:', err);
    process.exit(1);  // <-- fail-fast
  }
})();
```

**Say this:**
> "This is the server startup sequence. The entire startup is wrapped in an
> async IIFE — an Immediately Invoked Function Expression. Before `app.listen`
> is ever called, we read `schema.sql` and execute `CREATE TABLE IF NOT EXISTS`
> against the RDS database.
>
> The ordering is deliberate. If `app.listen` were called first and the schema
> query ran inside the listen callback — which was the original implementation —
> the server would already be accepting TCP connections while the table is
> still being created. An early request would hit a route that needs the
> transactions table before it exists.
>
> The other critical design decision is the catch block: `process.exit(1)`.
> If the database is unreachable or the schema query fails, the container
> crashes immediately. It does not limp forward with a broken DB layer. When
> the container crashes, ECS marks the task as unhealthy, the ALB stops
> routing traffic to it, and the deployment fails visibly rather than silently
> serving broken responses."

**Cross-Questions:**

> **"Why `process.exit(1)` and not just logging the error?"**
> "If we only log the error and the server starts anyway, the ALB health
> check hits `/health` and gets a 200 OK — because the Express server is
> running fine, it is just the database layer that is broken. The ALB would
> route real user traffic to a container that returns 500 errors on every
> database operation. The failure would be invisible to the deployment
> pipeline. `process.exit(1)` makes the failure loud and fast."

> **"What is `CREATE TABLE IF NOT EXISTS` doing for safety?"**
> "It makes the schema initialization idempotent. On the first boot against
> a blank RDS instance, it creates the table. On every subsequent boot, it
> is a no-op — the table already exists, the `IF NOT EXISTS` clause skips
> creation silently. This means we never accidentally drop and recreate a
> table with live data in it."

---

## FILE 7 — `backend/__tests__/api.test.js`

**Point to the mock setup at the top, then a real test block.**

```javascript
// Mock the whole service layer. The real db.js pool is never loaded, and
// env.js is only required by index.js, so neither needs a mock of its own.
jest.mock("../TransactionService", () => ({
  addTransaction:         jest.fn(),
  getAllTransactions:      jest.fn(),
  deleteAllTransactions:  jest.fn(),
  deleteTransactionById:  jest.fn(),
  findTransactionById:    jest.fn(),
}));
```

```javascript
describe("POST /transaction", () => {
  it("should return 201 when body is valid", async () => {
    transactionService.addTransaction.mockResolvedValue({
      id: 1, amount: 50, desc: "lunch",
    });
    const res = await request(app)
      .post("/api/transaction")
      .send({ amount: 50, desc: "lunch" });
    expect(res.statusCode).toBe(201);
    expect(res.body.message).toBe("added transaction successfully");
  });

  it("should return 400 when amount is missing", async () => {
    const res = await request(app)
      .post("/api/transaction")
      .send({ desc: "lunch" });
    expect(res.statusCode).toBe(400);
  });
});
```

**Say this:**
> "The test suite uses Jest and Supertest. The key design decision is at the
> top — we mock the TransactionService entirely, which is the only layer
> that talks to the database. The tests never need a real PostgreSQL
> connection. This means they run in milliseconds inside the CI pipeline
> without needing to provision any database infrastructure. (I originally
> also mocked the db pool and the env check, but I proved by running the
> suite with zero extra mocks that they were redundant, so I removed them.)
>
> The tests cover both the happy path and the validation path. `POST` with
> a valid body returns 201. `POST` with a missing `amount` field returns 400.
> This validates the input validation middleware is working correctly, not
> just that the happy path works.
>
> The CI pipeline runs `npm test` before it will build or deploy anything.
> A failing test blocks the entire pipeline."

**Cross-Questions:**

> **"Are these unit tests or integration tests?"**
> "They are technically integration tests because they test the full request-
> response cycle through Express routing, middleware, and service layer
> together. They are not unit tests of individual functions in isolation.
> With the database mocked, they do not test the actual SQL queries — that
> would require a real database, which is a valid next step using a tool
> like `pg-mem` (in-memory PostgreSQL) or a Docker-based test database
> in the CI pipeline."

---

## FILE 8 — `backend/db.js`

**Point to:**
```javascript
const pool = new Pool({
  host:     process.env.DB_HOST,
  user:     process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port:     process.env.DB_PORT || 5432,
  ssl: { rejectUnauthorized: false },
});
```

**Say this:**
> "The database connection pool. All configuration comes from environment
> variables injected by ECS at container startup — no hardcoded values.
>
> The critical line for AWS is `ssl: { rejectUnauthorized: false }`.
> AWS RDS enforces SSL-encrypted connections by default. Without this option,
> the Node.js `pg` client attempts an unencrypted connection and RDS
> rejects it with `no pg_hba.conf entry for host, no encryption`.
>
> `rejectUnauthorized: false` means SSL is used but the client does not
> validate the RDS certificate against a CA bundle. The correct production
> hardening is to download the AWS RDS CA certificate and set
> `rejectUnauthorized: true` with `ca: fs.readFileSync('rds-ca.pem')`.
> This is a known improvement item — SSL encryption is enforced, certificate
> validation is not."

**Cross-Questions:**

> **"Is `rejectUnauthorized: false` a security risk?"**
> "It means we are encrypted against passive eavesdropping but not protected
> against a man-in-the-middle attack that presents a fake certificate.
> In an AWS private subnet with no public internet route on RDS, the practical
> risk of a MITM attack is extremely low — an attacker would need to already
> be inside the VPC. In a compliance-sensitive environment (PCI, HIPAA), this
> would not be acceptable and the full CA certificate validation would be
> required."

---

## Closing the Demo

**Say this to wrap up:**
> "That covers the full stack — from the Terraform infrastructure definition,
> through the CI/CD pipeline, down to the application startup sequence and
> test suite.
>
> Every file we looked at has a direct connection to an architectural
> decision I made deliberately. None of this was copy-pasted from a tutorial
> and left as-is — each piece was adapted, debugged, and in some cases
> completely redesigned when the first approach failed in the real AWS
> environment."

---

## Files to have open and ready before the interview starts

Open these tabs in VS Code in order, minimized, ready to switch to:

1. `terraform/environments/prod/backend.tf`
2. `terraform/environments/prod/versions.tf`
3. `terraform/environments/prod/main.tf`
4. `terraform/environments/prod/outputs.tf`
5. `.github/workflows/deploy.yml`
6. `backend/index.js`
7. `backend/__tests__/api.test.js`
8. `backend/db.js`
