# Octa Byte — 30-Minute Technical Interview Script

> **How to use this:** Each segment has a target time. Read the opening line
> out loud exactly as written. The bullet points under each section are your
> talking points — expand on them naturally. The "Cross-Questions" at the end
> of every section are what interviewers almost always ask next; practice
> answering those cold before the interview.

---

## SEGMENT 1 — Opening & Project Overview (3 minutes)

**Opening line (say this verbatim):**
> "The Octa Byte project is a full-stack transaction management application.
> The application itself is straightforward — a React frontend, a Node.js
> Express backend, and a PostgreSQL database. My focus was not on the
> application code; it was on building an enterprise-grade cloud infrastructure
> around it. I want to walk you through the architectural decisions I made,
> why I made them, and the real trade-offs I considered for each one."

**Core talking points:**
- The deliverable is three things: **Infrastructure as Code** (Terraform),
  **a hardened network** (VPC + security groups), and **a fully automated
  CI/CD pipeline** (GitHub Actions).
- The application is deployed on AWS using ECS Fargate (serverless containers),
  RDS PostgreSQL (managed database), and an Application Load Balancer.
- Everything is provisioned through Terraform — there was no manual
  "click-ops" in the AWS console during provisioning.

**Cross-Question: "Walk me through the architecture at a high level before
we dive in."**

> "Sure. Traffic comes in from the internet and hits a single Application Load
> Balancer. The ALB has two forwarding rules: requests to `/api/*` go to the
> backend ECS service, everything else goes to the frontend ECS service. The
> ECS tasks run in private subnets — they cannot be reached directly from the
> internet. The database lives in an isolated subnet with no internet route
> whatsoever. Credentials are never hardcoded — the backend fetches its
> database password from AWS Secrets Manager at startup via an IAM role."

---

## SEGMENT 2 — Network Design: VPC & Subnets (5 minutes)

**Opening line:**
> "Let me start with the network, because every other security decision
> flows from the topology you establish here."

### 2a. Three-Tier Subnet Model

**What I built:**
- One VPC, three subnet tiers, replicated across **two Availability Zones**:
  - **Public subnet** — only the ALB lives here.
  - **Private compute subnet** — ECS Fargate tasks live here.
  - **Isolated data subnet** — RDS lives here, with no internet route at all.

**Why three tiers, not two?**
- The assignment required public and private subnets. A basic two-tier design
  puts the database in the same private subnet as the compute layer.
- If a security group is misconfigured, anything in that shared subnet can
  reach the database directly.
- Three tiers means two separate mistakes need to happen before the database
  is exposed, not one.

**Why two Availability Zones?**
- A single-AZ architecture has no answer to "what happens if that AZ has
  an outage?" The interviewer will ask this — a single AZ is not highly
  available by any reasonable definition.

**What I did NOT do and why:**
- I did not use three AZs. Two is the minimum for High Availability and
  sufficient for this workload. Three AZs triples NAT Gateway costs.
- I did not use a Transit Gateway or VPC Peering because this is a
  self-contained application.

**Cross-Questions:**

> **"Why not just put everything in public subnets for simplicity?"**
> "If the ECS tasks or RDS were in public subnets, they would have public
> IP addresses and be directly reachable from the internet. You're then
> relying entirely on security group rules to protect them. Defense in depth
> means the network topology itself should be the first line of defense —
> private subnets enforce that before any security group rule is even
> evaluated."

> **"What is the NAT Gateway for?"**
> "ECS tasks in private subnets need to make outbound internet connections —
> specifically to pull Docker images from ECR and to call AWS APIs like
> Secrets Manager. The NAT Gateway lets them initiate outbound connections
> while remaining unreachable from inbound internet traffic."

> **"How much does a NAT Gateway cost?"**
> "Roughly $0.045 per hour plus $0.045 per GB of data processed, so around
> $32/month at minimum. For a production environment this is non-negotiable.
> For dev/test environments, the standard cost-optimization is to use a
> NAT Instance (a small EC2 running a NAT AMI) which can run for $5-10/month,
> at the cost of managing it yourself."

---

### 2b. Security Groups: SG-to-SG Chaining

**What I built:**
- Each ECS service has its own security group (frontend and backend). Its
  inbound rule references the ALB security group ID, not a CIDR range, and
  only on that service's own port (80 / 4000).
- The RDS security group's inbound rule references the **backend** ECS
  security group ID only, so the frontend tasks have no path to the database.
  (They originally shared one group, which let the frontend reach RDS. See
  challenge 15.)

**Why SG references instead of IP ranges?**
- Fargate tasks get brand new Elastic Network Interfaces on every deployment.
  Their IP addresses change constantly.
- A CIDR-based rule like "allow 10.0.0.0/16" allows anything in that entire
  VPC to reach the database — including future resources that should not have
  that access.
- An SG reference says "only traffic from this specific logical group of
  resources is allowed," regardless of what IP addresses they have.

**Cross-Questions:**

> **"Why not just allow the private subnet CIDR to reach RDS?"**
> "That would work initially, but it doesn't scale safely. If you later add
> a data processing Lambda or a bastion host in the same private subnet, they
> would automatically inherit database access even though they shouldn't have
> it. SG-to-SG chaining scopes access to the specific resource type, not its
> network location."

> **"What does the ALB security group look like?"**
> "The ALB security group allows inbound port 80 from 0.0.0.0/0 (the public
> internet). There's no 443 yet because I didn't add HTTPS; that's a known
> gap. Each ECS service has its own security group that allows inbound only
> from the ALB SG, on its own port. RDS allows inbound only from the backend
> ECS SG. It is a strict chain with no shortcuts, and the frontend tasks have
> no path to the database. (Outbound is open on the ALB and ECS groups so
> tasks can reach ECR, Secrets Manager and CloudWatch through the NAT.)"

---

## SEGMENT 3 — Security Posture (5 minutes)

**Opening line:**
> "Security was not something I added at the end. I made decisions at
> every layer to reduce the attack surface."

### 3a. AWS Secrets Manager + manage_master_user_password

**What I built:**
- In the Terraform RDS module, I set `manage_master_user_password = true`.
- This tells AWS to generate the password, store it in Secrets Manager, and
  handle rotation natively.
- The Terraform state file never contains the database password.

**Why this approach?**
- The alternative is using Terraform's `random_password` resource, then
  manually creating a Secrets Manager secret and wiring the ARN into the
  ECS task definition. That is more code, more places to make a mistake,
  and manually reimplementing something AWS already offers as one boolean flag.

**How the backend actually gets the password:**
- The ECS Task Definition has a `secrets` block that maps the secret ARN to
  an environment variable name (`DB_PASSWORD`).
- The **Task Execution Role** (not the task role) has an explicit IAM policy
  granting `secretsmanager:GetSecretValue` on that specific secret's ARN.
- ECS pulls the secret before the container starts and injects it into memory.
  It never touches disk.

**Real bug I hit and fixed:**
- The backend task kept failing at start-up with `AccessDeniedException` on
  the secret. The real fix was granting the task execution role permission
  to read it (`task_exec_secret_arns`); I'd simply not granted it.
- While debugging I also added a trailing wildcard to the ARN
  (`"${arn}*"`), because Secrets Manager appends a random 6-character suffix
  to every secret ARN. In hindsight the module's output ARN already includes
  that suffix, so the wildcard is probably unnecessary. I kept it as a
  defensive safety net and haven't re-tested without it. Say it that way:
  it shows you know the difference between the root cause and a precaution.

**Cross-Questions:**

> **"What's the difference between a Task Role and a Task Execution Role?"**
> "The Task Execution Role is used by the ECS agent itself — the AWS
> infrastructure — before your container code runs. It needs permissions to
> pull the Docker image from ECR, fetch secrets from Secrets Manager, and
> write logs to CloudWatch. The Task Role is what your application code uses
> at runtime to call other AWS services. In this project, the backend doesn't
> call any AWS APIs directly, so the task role doesn't need any custom
> permissions — only the execution role needed the Secrets Manager grant."

> **"What happens if Secrets Manager is unavailable at container startup?"**
> "The container fails to start. ECS marks the task as failed and the ALB
> health check detects it. Because we're using rolling updates, the old
> containers stay in rotation until the new ones pass health checks. A
> Secrets Manager outage is a regional AWS event — very rare, but the correct
> response is to have the RDS credentials cached in a parameter store or
> sidecar for true resilience, which is a known improvement item."

---

### 3b. GitHub Actions OIDC (No Stored AWS Keys)

**What I built:**
- The GitHub Actions pipeline uses OpenID Connect (OIDC) to authenticate
  to AWS. There is no `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` stored
  as a GitHub secret.

**How it works:**
- GitHub's OIDC provider issues a short-lived signed JWT token for each
  workflow run.
- AWS's IAM OIDC Identity Provider is configured to trust GitHub's JWT issuer.
- The workflow calls `sts:AssumeRoleWithWebIdentity`, exchanging the JWT for
  temporary AWS credentials valid for the duration of the pipeline run only.

**Why not long-lived access keys?**
- Long-lived keys stored as GitHub secrets are a standing liability. If the
  repository is compromised, those keys are valid until manually rotated.
- OIDC tokens have a TTL of minutes. A leaked OIDC token from a completed
  run is useless.

**Real debugging story (this is a strong one):**
- After wiring up OIDC, the pipeline kept failing with
  `Not authorized to perform sts:AssumeRoleWithWebIdentity`.
- The IAM trust policy's `StringLike` condition on the `sub` claim was
  using the old format: `repo:username/reponame:*`.
- GitHub had migrated this account to an immutable claim format that uses
  numeric IDs instead of usernames in the `sub` claim to prevent trust-policy
  hijacking when a repo is renamed or deleted and recreated.
- I decoded the actual JWT from a failed run using jwt.io to see the real
  `sub` claim, then updated the IAM trust policy to match it exactly.

**Cross-Questions:**

> **"What is the sub claim and why does it matter for security?"**
> "The `sub` claim is what GitHub embeds in the OIDC token to identify
> exactly which repository and workflow issued it. The IAM trust policy uses
> this claim as a condition. Without it, any GitHub repository could
> potentially exchange a token for credentials in your AWS account. The `sub`
> claim scopes the trust to your specific repository only."

> **"Why not use IAM roles with EC2 instance profiles in the runner?"**
> "GitHub Actions runs on GitHub-managed Ubuntu runners, not on EC2 instances
> we control, so instance profiles aren't applicable here. The equivalent
> for managed CI runners is OIDC — it is the recommended practice in GitHub's
> own AWS documentation."

---

## SEGMENT 4 — Compute, Routing & Database (6 minutes)

**Opening line:**
> "With the network and security established, let me walk through the
> compute and routing decisions."

### 4a. ECS Fargate over EC2 or EKS

**What I chose:** ECS on Fargate.

**Why Fargate over EC2-based ECS?**
- EC2 ECS requires managing a cluster of EC2 instances: choosing instance
  types, patching the OS, planning capacity, handling spot interruptions.
- Fargate is serverless compute. You define the container, the CPU, and the
  memory. AWS handles everything underneath. There are no nodes to patch.

**Why ECS over EKS (Kubernetes)?**
- Kubernetes gives you powerful primitives: deployments, services, ingress
  controllers, horizontal pod autoscaler, custom resource definitions.
- For a two-service application on a single cloud provider, that operational
  complexity is not earned. EKS has real maintenance overhead — cluster
  upgrades, node group management, and a steeper learning curve.
- The right question is "what does this application actually need?" Not
  "what is the most impressive tool?"

**Trade-off to acknowledge honestly:**
- Fargate costs more per vCPU/GB than equivalent EC2 capacity. For large,
  steady workloads, EC2 spot instances would be significantly cheaper.
- For a small, bursty application where operational savings outweigh compute
  cost premium, Fargate is the correct call.

**Cross-Questions:**

> **"When would you pick EKS instead?"**
> "When you need Kubernetes-native ecosystem tooling that doesn't exist in
> ECS — service meshes like Istio, Argo CD for GitOps, or if you're running
> a multi-cloud or hybrid environment where portability across platforms is
> a requirement. For a single AWS-native application, ECS is simpler and
> sufficient."

> **"How does ECS handle scaling?"**
> "ECS has built-in Application Auto Scaling. You can set a minimum and
> maximum task count and attach a scaling policy based on CloudWatch metrics
> — CPU utilization, memory utilization, or ALB request count per target.
> When CPU exceeds a threshold, ECS launches additional tasks. Fargate
> provisions the compute for them automatically."

---

### 4b. Application Load Balancer with Path-Based Routing

**What I built:**
- One ALB, one listener on port 80.
- Default action: forward to the frontend target group.
- One listener rule: requests matching `/api/*` forward to the backend
  target group.

**Why one ALB instead of two?**
- Two ALBs means two DNS names. The frontend code needs to know the backend's
  ALB hostname. That hostname is environment-specific, changes between
  deployments, and introduces CORS complexity.
- One ALB, one DNS name, one origin for the browser. Path-based routing
  handles the separation cleanly.

**Why not API Gateway in front of the backend?**
- API Gateway is a heavier tool: it adds schema validation, throttling, API
  keys, usage plans, and SDK generation.
- For an internal service consumed only by your own frontend, that is
  unnecessary complexity and an added cost per million requests.

**Why not Nginx proxy on the frontend to route `/api` calls?**
- This is exactly the failure mode I hit in production. In my original local
  docker-compose setup (not committed to this repo), containers shared a
  network with service discovery DNS (container names resolve as hostnames). In ECS with `awsvpc` networking,
  each task gets its own ENI — there is no built-in DNS name "backend" for
  Nginx to proxy_pass to unless you configure ECS Service Connect explicitly.
- Moving the routing responsibility to the ALB was architecturally cleaner
  because the ALB already has visibility into both target groups.

**Cross-Questions:**

> **"What happens to HTTPS?"**
> "For a production workload, you would add a port 443 listener, attach an
> ACM certificate, and redirect port 80 to 443. This project uses port 80
> because the assignment did not require a domain name or TLS termination.
> It is a known gap and the fix is straightforward — one ACM certificate
> request and two listener changes in Terraform."

> **"How does the ALB know a container is healthy?"**
> "Each target group has a health check configured. The backend exposes a
> `/health` endpoint that returns 200 OK. The ALB sends a GET request to this
> endpoint every 30 seconds. A task must pass a configurable number of
> consecutive health checks before the ALB adds it to the rotation, and fail
> a configurable number before it removes it. This is what enables
> zero-downtime rolling deployments."

---

### 4c. RDS PostgreSQL Deployment Choices

**Why managed RDS over self-hosted Postgres on EC2?**
- Self-hosted Postgres on EC2 means managing backups, replication,
  failover, and OS patching. RDS handles all of this natively.
- Multi-AZ RDS provides automatic failover — if the primary instance fails,
  AWS promotes the standby in a different AZ in under two minutes with no
  application code change. **This deployment is single-AZ** (`multi_az` is
  off) to save cost; turning it on is a one-line change and the first thing
  I'd do for real availability. Be ready to say that unprompted.

**Schema initialization (real production problem I solved):**
- AWS RDS provisions a completely blank database instance. Unlike
  `docker-compose` which can run SQL init scripts via entrypoint hooks,
  there is no built-in mechanism to apply a schema.
- The fix: `index.js` wraps the entire server startup in an async IIFE.
  It reads `schema.sql` and executes `CREATE TABLE IF NOT EXISTS` before
  calling `app.listen()`. If this query fails, it calls `process.exit(1)`.
  The server never starts in a broken state.

**Cross-Questions:**

> **"Why not use a proper migration tool like Flyway or Liquibase?"**
> "That is absolutely the correct approach for a production system with
> evolving schemas. Migration tools maintain a version history, support
> rollbacks, and handle team collaboration on schema changes safely.
> For this project, the schema is a single table that is idempotent via
> `CREATE TABLE IF NOT EXISTS`. A dedicated migration tool is the right
> 'given more time' improvement."

---

## SEGMENT 5 — CI/CD Pipeline (4 minutes)

**Opening line:**
> "The pipeline is the glue that makes the infrastructure self-service.
> A developer pushes code and the pipeline handles everything else."

**Pipeline structure (three sequential jobs):**

1. **Test & Security Scan** (runs on every PR and push):
   - Installs dependencies, runs the Jest unit test suite.
   - Runs `npm audit --audit-level=high` to flag known dependency vulnerabilities.

2. **Build & Push** (runs only on merge to main):
   - Authenticates to AWS via OIDC.
   - Builds Docker images for both frontend and backend.
   - Tags them with the Git commit SHA — not `latest`.
   - Runs **Trivy** container scanning on both images.
   - Pushes to ECR only after Trivy passes.

3. **Deploy to Production** (runs after build succeeds, requires manual
   environment approval in GitHub):
   - Downloads the current live task definition from ECS via
     `aws ecs describe-task-definition`.
   - Uses `amazon-ecs-render-task-definition` to inject the new image URI
     into the task definition.
   - Deploys via `amazon-ecs-deploy-task-definition` which triggers a
     rolling update.
   - The backend deployment waits for service stability. The frontend
     deployment does not (deliberate time-saving trade-off).

**Why immutable image tags (Git SHA)?**
- `latest` is mutable — you cannot tell from a running container what code
  it contains. With a Git SHA tag, you can trace a running container back to
  the exact commit, diff, and author in seconds.
- Rollback is also trivial: find the previous task definition revision
  (it still references the old SHA), force a deployment. No rebuild needed.

**Why Trivy and not just `npm audit`?**
- `npm audit` only scans Node.js dependencies in `package.json`. Trivy
  scans the entire container image including the base OS layer (e.g., Alpine
  or Debian packages). OS-level CVEs are a common attack vector that
  `npm audit` would miss entirely.

**Honest trade-off to acknowledge:**
- Trivy is configured with `exit-code: 0` — it reports findings but does not
  block the pipeline. The correct production setup is `exit-code: 1` for
  CRITICAL findings to block the build, but with a documented exception/waiver
  process for CVEs with no available patch yet.

**Cross-Questions:**

> **"What happens if the new container fails health checks after deployment?"**
> "The rolling update only drains and terminates old tasks after new ones
> pass the ALB health check. If new tasks fail health checks, ECS marks the
> deployment as failed and stops replacing old tasks. The old version stays
> in service. ECS does not automatically roll back — you would need to force
> a new deployment using the previous task definition revision. In a mature
> setup, you add a CloudWatch alarm that triggers a Lambda to auto-rollback
> on deployment failure."

> **"Why use a manual approval gate for production?"**
> "GitHub Environments with required reviewers act as a pause button between
> build and deploy. The pipeline can build and scan the image automatically,
> but an engineer must explicitly approve before anything goes to production.
> This is a common compliance control in regulated environments — an automated
> build does not equal an authorized release."

---

## SEGMENT 6 — Infrastructure as Code Decisions (4 minutes)

**Opening line:**
> "Let me talk about the Terraform design decisions specifically."

### Terraform Registry Modules vs Hand-Rolled Resources

**What I used:** `terraform-aws-modules/{vpc,alb,ecs,rds,security-group}/aws`

**Why modules?**
- These are the de facto community standard. They are heavily tested, reviewed
  by thousands of engineers, and encode AWS best practices by default.
- The VPC module alone handles subnet creation, route table associations,
  IGW attachment, and NAT Gateway provisioning. Writing all of that from
  scratch is hundreds of lines of repetitive resource definitions with a
  high probability of subtle misconfiguration.

**Honest acknowledgment:**
- Using modules means less line-by-line ownership of every resource.
  The risk is using a module without reading what it actually provisions.
  For every module in this build, the actual source code and documentation
  was read before using it — this is how I caught that the ECS module
  defaults `readonly_root_filesystem = true`, which caused the Nginx crash.

**S3 Remote State with Native Locking:**
- Terraform state is stored in an S3 bucket with versioning enabled.
- Locking is handled via `use_lockfile = true` in the backend configuration.
  This is a Terraform 1.10+ feature that uses S3 conditional writes to
  implement locking natively — no DynamoDB table required.
- Most tutorials still show DynamoDB locking. The project is running Terraform
  1.15.8, well past the 1.10 threshold. Knowing when the ecosystem has moved
  past a legacy pattern is part of keeping infrastructure current.

**Modular code structure:**
- The codebase is split into reusable modules (vpc, ecs, rds, alb,
  security-group). Each module accepts input variables.
- This means the same code could provision a staging environment with a
  different `.tfvars` file — no copy-pasting of resource blocks.

**Cross-Questions:**

> **"Why Terraform over CloudFormation?"**
> "CloudFormation is AWS-only. Terraform is cloud-agnostic — the same mental
> model, state management, and tooling applies across AWS, GCP, and Azure.
> Terraform also has a significantly larger module ecosystem and a more
> readable HCL syntax compared to CloudFormation's JSON/YAML. For an
> AWS-native shop with no multi-cloud requirements, CloudFormation is a
> perfectly valid choice. For a team that works across clouds, Terraform is
> a better default."

> **"How do you manage Terraform in a team environment?"**
> "Remote state in S3 is the foundation — everyone reads from and writes to
> the same state file. State locking prevents concurrent applies. Beyond that,
> you would add a CI/CD workflow for `terraform plan` on PRs (so team members
> can review the diff before merging) and `terraform apply` on merge. Tools
> like Atlantis or Terraform Cloud provide this as a managed service."

---

## SEGMENT 7 — Observability (2 minutes)

**Opening line:**
> "The assignment required infrastructure metrics, application metrics,
> database metrics, centralized logging, and at least two dashboards."

**What I built:**
- All ECS task logs are forwarded to CloudWatch Log Groups
  (`/aws/ecs/<service>/<container>`, 30-day retention) via the `awslogs`
  log driver — zero configuration on the application side.
- RDS CloudWatch metrics (CPU, connections) feed the alarms and dashboard.
  RDS Performance Insights is **not** enabled; it would be a one-flag
  addition (check instance-class support) and is the natural next step.
- CloudWatch Container Insights provides CPU, memory, and network metrics
  at the cluster, service, and task level.
- CloudWatch Dashboards were created to surface the key operational metrics
  in one view.

**Why CloudWatch over Prometheus/Grafana/Datadog?**
- The assignment requirement is tool-agnostic. CloudWatch satisfies every
  listed item natively with zero additional infrastructure to provision,
  secure, or pay for.
- In a mature production environment, Datadog or Grafana + Prometheus would
  give significantly richer dashboards, better alerting, and cross-service
  correlation. But those require deploying agents, managing an additional
  platform, and paying for a separate service.
- For this deliverable, using CloudWatch was the pragmatic, cost-effective
  correct call given the explicit tool-agnostic requirement.

**Cross-Questions:**

> **"Have you used Prometheus or Grafana?"**
> Be honest here. If you haven't: "Not in a production context on this
> project — CloudWatch was the right call for the requirements. I understand
> the Prometheus data model (pull-based scraping, PromQL) and how Grafana
> visualizes metrics data sources, but my hands-on work with this stack used
> CloudWatch."

---

## SEGMENT 8 — Closing (1 minute)

**Closing line (say this verbatim):**
> "To summarize the design philosophy: every decision in this architecture
> was made to reduce operational risk. The three-tier VPC reduces blast
> radius. Secrets Manager eliminates credential exposure. OIDC eliminates
> long-lived keys. Fargate eliminates server management. Immutable image
> tags enable precise traceability and instant rollback. And Terraform makes
> the entire environment reproducible from source code.
>
> I'm happy to go deeper on any of these layers, pull up the actual
> Terraform code, or walk through specific debugging incidents — whatever is
> most useful for you."

---

## QUICK REFERENCE: Cross-Questions Cheat Sheet

| Question | One-line Answer |
|---|---|
| Why Fargate over EC2? | No node patching, no capacity planning, scales at container level |
| Why ECS over EKS? | EKS operational overhead not justified for a two-service app |
| Why three subnet tiers? | Two mistakes needed to expose DB, not one |
| Why SG references not CIDR? | Fargate IPs change every deploy; CIDR is too broad |
| Why Secrets Manager? | Credentials never in state file, code, or CI secrets |
| Task role vs execution role? | Execution = ECS pulling image/secrets; Task = app calling AWS at runtime |
| Why OIDC not stored keys? | OIDC tokens expire in minutes; leaked stored keys are valid forever |
| Why immutable SHA tags? | Exact traceability, instant rollback without rebuild |
| Why native S3 locking not DynamoDB? | Terraform 1.10+ feature; DynamoDB locking is a legacy pattern |
| Why ALB not API Gateway? | API Gateway is overkill for an internal service; adds cost and complexity |
| Why one ALB not two? | One DNS name, no CORS complexity, half the cost |
| Why `use_lockfile = true`? | Native S3 conditional write locking — no extra infrastructure |
| Why CloudWatch not Datadog? | Zero extra infrastructure; satisfies all tool-agnostic requirements |
| How does rollback work? | Force deploy previous ECS task definition revision — no rebuild |
| What about HTTPS? | ACM certificate + 443 listener; known gap, straightforward fix |
| Why schema init in app code? | No migration tool for simplicity; idempotent `CREATE TABLE IF NOT EXISTS` |
