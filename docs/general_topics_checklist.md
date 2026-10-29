# General Interview Topics — DevOps / Cloud Engineer / SRE / Junior Architect

> Unlike the other files in `docs/`, this one is NOT about the Octa Byte
> project. It's the broader map of what this role family gets asked about
> in general. Use it to find gaps — topics you haven't touched at all —
> separate from the deep, project-specific prep in the other files.
>
> **Priority tags**, since this is a junior-level role:
> `[CORE]` = expect this to come up, know it cold.
> `[GOOD TO KNOW]` = common, but shallower depth is fine at this level.
> `[AWARENESS]` = know the term and the one-sentence idea; deep expertise not expected yet.
>
> Where a topic overlaps with something this project already demonstrates
> hands-on, that's noted — those are the ones where you have a *real story*,
> not just a definition, and interviewers can tell the difference.

---

## 1. Linux & Operating System Fundamentals

- `[CORE]` File permissions (`chmod`, `chown`, octal notation, setuid/setgid)
- `[CORE]` Processes: `ps`, `top`/`htop`, signals (`SIGTERM` vs `SIGKILL` vs `SIGINT`), zombie/orphan processes
  — *you have a real story here*: graceful shutdown on SIGTERM in `backend/index.js`
- `[CORE]` systemd basics: units, `systemctl start/enable/status`, journald logs
- `[CORE]` SSH: key-based auth (public/private keypair, `~/.ssh/authorized_keys`), `ssh-agent`, `~/.ssh/config` host aliases, port forwarding/tunneling — the baseline access mechanism under almost everything else in this list (git over SSH, `scp`, Ansible's transport, EC2 instance access before SSM existed)
- `[GOOD TO KNOW]` Filesystems: inodes, hard vs symbolic links, disk usage (`df`, `du`), mount points
- `[GOOD TO KNOW]` Networking tools: `netstat`/`ss`, `curl`/`wget`, `dig`/`nslookup`, `tcpdump`, `traceroute`
- `[GOOD TO KNOW]` Package managers (`apt`, `yum`/`dnf`, `apk`) and why Alpine (`apk`) matters for small container images
- `[GOOD TO KNOW]` Users & groups (`useradd`/`usermod`, `/etc/passwd` vs `/etc/shadow`, `sudo` and `/etc/sudoers`) — who can do what on a box, distinct from file permissions (what they can do *to a file*)
- `[GOOD TO KNOW]` Text-processing tools: `grep`, `awk`, `sed` — the three you reach for to find/transform/filter text in logs or config without opening an editor
- `[AWARENESS]` cron / systemd timers for scheduled jobs
- `[AWARENESS]` `/proc` filesystem, load average, basic perf triage (`vmstat`, `iostat`)
- `[AWARENESS]` Log rotation (`logrotate`) — why logs don't just grow forever and fill the disk

---

## 2. Networking Fundamentals

- `[CORE]` OSI model (at least L3/L4/L7 distinctions) and TCP vs UDP
- `[CORE]` DNS: record types (A, CNAME, MX, TXT, NS), how resolution works, TTLs
- `[CORE]` HTTP/HTTPS: status codes, headers, methods, idempotency of verbs
- `[CORE]` TLS/SSL handshake basics, certificates, what a CA does
  — *real story*: the `rejectUnauthorized: false` trade-off in `db.js`
- `[CORE]` CIDR notation and subnetting math (prefix length, host count, netmask)
  — *real story*: the `cidrsubnet()` three-tier VPC design
- `[CORE]` Load balancing: L4 vs L7, round robin vs least-connections, health checks
  — *real story*: the ALB path-based routing setup
- `[GOOD TO KNOW]` NAT (and NAT Gateway vs NAT instance cost trade-off)
  — *real story*: single NAT Gateway decision in this project
- `[GOOD TO KNOW]` Reverse proxy vs forward proxy, what a CDN actually does (edge caching, origin shielding)
- `[GOOD TO KNOW]` VPNs, Direct Connect, VPC peering vs Transit Gateway (when each makes sense)
- `[AWARENESS]` BGP, anycast — know the term, not the deep mechanics

---

## 3. Cloud Platform Fundamentals (AWS-primary; know the GCP/Azure equivalent name)

| Category | AWS | GCP | Azure |
| --- | --- | --- | --- |
| VM compute | EC2 | Compute Engine | Virtual Machines |
| Serverless functions | Lambda | Cloud Functions | Azure Functions |
| Containers (serverless) | Fargate | Cloud Run | Container Instances |
| Managed Kubernetes | EKS | GKE | AKS |
| Object storage | S3 | Cloud Storage | Blob Storage |
| Block storage | EBS | Persistent Disk | Managed Disks |
| Managed relational DB | RDS/Aurora | Cloud SQL | Azure SQL |
| Managed NoSQL | DynamoDB | Firestore/Bigtable | Cosmos DB |
| Queues | SQS | Pub/Sub | Service Bus |
| Pub/sub fan-out notifications | SNS | Pub/Sub | Service Bus (topics) |
| DNS | Route 53 | Cloud DNS | Azure DNS |
| CDN | CloudFront | Cloud CDN | Azure CDN |
| API management/gateway | API Gateway | Apigee / API Gateway | API Management |
| Workflow orchestration | Step Functions | Workflows | Logic Apps |
| Identity for app users | Cognito | Identity Platform | Azure AD B2C |
| Managed encryption keys | KMS | Cloud KMS | Key Vault |
| IaC-native tool | CloudFormation | Deployment Manager | ARM / Bicep |

- `[GOOD TO KNOW]` The named services above a junior AWS Solutions Architect
  posting will typically call out by name even though this project doesn't
  use them directly: **Route 53** (DNS + health-check-based failover),
  **CloudFront** (CDN in front of S3/ALB), **API Gateway** (the managed
  front door for Lambda/REST APIs, handling throttling/auth/API keys so you
  don't hand-roll them), **SNS** (pub/sub fan-out to multiple subscribers —
  the complement to SQS's point-to-point queue), **Step Functions**
  (orchestrating a multi-step workflow across Lambdas/services as a state
  machine, instead of one function awkwardly calling the next), **Cognito**
  (user sign-up/login/token issuance for an app, as opposed to IAM which is
  for *infrastructure* access), **KMS** (the service actually generating
  and managing the encryption keys behind "encryption at rest" — e.g. what
  sits under your RDS/EBS encryption flag).
- `[CORE]` **CloudTrail** vs **CloudWatch** — the distinction interviewers
  like to probe: CloudTrail is the audit log of *who called which API and
  when* (an IAM-level "who did this"); CloudWatch is metrics/logs about
  *application and infra behavior*. You need both — CloudTrail for "who
  deleted that security group," CloudWatch for "why did latency spike."
- `[GOOD TO KNOW]` **EFS (Elastic File System)** — shared, POSIX-compliant
  file storage mountable by multiple instances/containers at once, vs
  EBS which attaches to exactly one instance at a time — the thing you'd
  reach for if several ECS tasks needed to read/write the *same* files.
- `[GOOD TO KNOW]` **Auto Scaling Groups (ASG)** — EC2-level scaling
  (launch template + min/max/desired + scaling policies), distinct from
  ECS Service Auto Scaling or the HPA in Kubernetes — same *idea*, different
  layer of the stack doing the scaling.
- `[AWARENESS]` **WAF** (Web Application Firewall — blocks common web
  exploits like SQLi/XSS at the edge, in front of CloudFront/ALB) and
  **Shield** (DDoS protection, Standard is free/automatic, Advanced is
  paid) — know these exist as the "edge protection" layer above
  network-level security groups.
- `[CORE]` IAM concepts: principle of least privilege, roles vs users vs policies, resource-based vs identity-based policies
  — *real story*: Task Execution Role vs Task Role, OIDC federation for GitHub Actions
- `[CORE]` VPC fundamentals: subnets, route tables, internet/NAT gateways, security groups vs NACLs (stateful vs stateless!)
  — *real story*: the whole three-tier VPC in this project
- `[CORE]` Shared Responsibility Model (what AWS secures vs what you secure)
- `[GOOD TO KNOW]` Secrets management (Secrets Manager vs Parameter Store vs Vault — when to use which)
  — *real story*: `manage_master_user_password = true`
- `[GOOD TO KNOW]` Multi-region vs multi-AZ — what each actually protects against
- `[GOOD TO KNOW]` Cost basics: On-Demand vs Reserved vs Spot vs Savings Plans, and roughly when each applies
- `[AWARENESS]` Well-Architected Framework pillars (Operational Excellence, Security, Reliability, Performance Efficiency, Cost Optimization, Sustainability) — know the six names and what each is about

---

## 4. Containers & Orchestration

- `[CORE]` Docker fundamentals: images vs containers, layers and caching, `Dockerfile` best practices (multi-stage builds, minimizing layers, non-root user)
  — *real story*: the Nginx read-only-filesystem crash (workaround: writable root; proper fix is a `tmpfs` mount, not yet done)
- `[CORE]` Image registries, tagging strategy (why `latest` is dangerous)
  — *real story*: git-SHA image tags in this project's CI/CD
- `[CORE]` Container vs VM — what's actually different (shared kernel, namespaces, cgroups at a conceptual level)
- `[GOOD TO KNOW]` Kubernetes core objects: Pod, Deployment, Service, Ingress, ConfigMap, Secret, Namespace
- `[GOOD TO KNOW]` Kubernetes networking basics: how a Service gets traffic to a Pod, what kube-proxy does
- `[GOOD TO KNOW]` Horizontal Pod Autoscaler, resource requests/limits, readiness vs liveness probes
  — *related story*: ALB health checks serve the same purpose as K8s readiness probes — good bridge if asked "how would this look in K8s?"
- `[GOOD TO KNOW]` ECS vs EKS vs Fargate vs self-managed K8s — trade-offs
  — *real story*: you already have the ECS-vs-EKS reasoning from this project
- `[AWARENESS]` Helm (templated K8s manifests), Operators, service mesh (Istio/Linkerd — what problem they solve: mTLS, traffic shaping, observability between services)
- `[CORE]` **Docker Compose** — defining a multi-container local dev stack
  (app + DB + cache) in one `docker-compose.yml`, `docker compose up` to
  run it all with shared networking — the thing almost every junior
  candidate has actually used, even without ECS/K8s experience; worth
  naming explicitly if your own local dev setup used it.
- `[GOOD TO KNOW]` Kubernetes workload types beyond Deployment:
  **StatefulSet** (stable network identity + stable storage per replica —
  for things like databases where "which replica" matters, unlike
  stateless web Pods), **DaemonSet** (exactly one Pod per node — log
  collectors, node-level monitoring agents), **Job / CronJob** (run-to-
  completion batch work, one-off or scheduled — the K8s equivalent of a
  cron entry, but containerized and cluster-scheduled).
- `[GOOD TO KNOW]` Kubernetes storage: **PersistentVolume (PV)** /
  **PersistentVolumeClaim (PVC)** / **StorageClass** — how a Pod gets
  durable disk that survives a restart, the rough equivalent of attaching
  an EBS volume to a task instead of relying on ephemeral container
  storage.
- `[GOOD TO KNOW]` **RBAC** (Role/RoleBinding, ClusterRole/ClusterRoleBinding)
  — who can do what *inside* the cluster, the K8s-native equivalent of IAM
  policies, scoped to Kubernetes API objects instead of AWS resources.
- `[AWARENESS]` **NetworkPolicy** — firewall rules for pod-to-pod traffic
  inside the cluster (the K8s equivalent of security groups, since by
  default every Pod can talk to every other Pod).
- `[AWARENESS]` **Taints & tolerations** / **node affinity** — steering
  which Pods are allowed to (or must) land on which nodes — e.g. keeping
  GPU workloads off general-purpose nodes.

---

## 5. CI/CD & Release Engineering

- `[CORE]` What CI vs CD actually means, and continuous delivery vs continuous deployment (the human-approval distinction)
  — *real story*: your manual GitHub Environment approval gate
- `[CORE]` Named CI/CD tools beyond the one you used: **Jenkins** (the
  long-standing self-hosted, plugin-driven standard — still widely run),
  **GitLab CI** (pipeline defined in `.gitlab-ci.yml`, tightly integrated
  with GitLab's own repo/registry), **CircleCI** (hosted, config-as-YAML,
  popular for its caching/parallelism model), **Azure DevOps Pipelines**
  (common in Microsoft-shop environments), **Bamboo** (Atlassian's,
  usually paired with Jira/Bitbucket). You used **GitHub Actions** — be
  ready to say *why* it fit here (repo-native, no separate server to run)
  and that the YAML-pipeline-as-config concept transfers directly to any
  of the others.
- `[CORE]` Build artifact immutability — same idea as git-SHA tags, applies to any artifact type
- `[CORE]` Deployment strategies: rolling, blue-green, canary — what each protects against and costs
- `[GOOD TO KNOW]` GitOps (ArgoCD/Flux): declarative deploys driven by a git repo as source of truth, vs an imperative pipeline pushing changes
- `[GOOD TO KNOW]` Secrets in CI/CD: why long-lived keys are risky, OIDC/short-lived federation as the fix
  — *real story*: this is your strongest CI/CD story in the whole project
- `[GOOD TO KNOW]` Trunk-based development vs GitFlow — trade-offs for release cadence
- `[AWARENESS]` Feature flags as a decoupling mechanism between deploy and release

---

## 6. Infrastructure as Code

- `[CORE]` Declarative vs imperative IaC, and why idempotency matters
- `[CORE]` Terraform core concepts: state, plan/apply, providers, modules, variables/outputs
  — *real story*: you can speak to this at real depth already
- `[CORE]` State locking and why concurrent applies are dangerous without it
  — *real story*: S3 native locking vs DynamoDB
- `[GOOD TO KNOW]` Terraform workspaces vs separate state files per environment — trade-offs
- `[GOOD TO KNOW]` Drift detection — what causes config drift (manual console changes) and how `terraform plan` surfaces it
- `[GOOD TO KNOW]` Config management tools (Ansible, Chef, Puppet) — how they differ from provisioning tools like Terraform (configuring existing hosts vs creating infrastructure)
- `[AWARENESS]` Policy-as-code (OPA/Sentinel) — automated guardrails on what Terraform is allowed to apply
- `[AWARENESS]` Pulumi / CDK — IaC using real programming languages instead of HCL/YAML
- `[GOOD TO KNOW]` Terraform mechanics worth naming cold: **data sources**
  (reading an existing, unmanaged resource — e.g. an AMI lookup — vs
  `resource` blocks which create/own one), **`count`/`for_each`** (looping
  to create N similar resources instead of copy-pasting a block),
  **`lifecycle` blocks** (`prevent_destroy` to stop an `apply` from ever
  deleting something critical like a prod DB, `create_before_destroy` for
  zero-downtime replacement), and the **Terraform Registry** (where
  published providers and reusable modules live).
- `[AWARENESS]` Provisioners (`local-exec`/`remote-exec`) — running a
  script as part of a resource's create/destroy; generally considered a
  last resort since Terraform's model is declarative state, not scripted
  steps, and most of what provisioners are used for is better done with
  cloud-init/user-data or a config management tool.

---

## 7. Observability & Monitoring

- `[CORE]` The three pillars: metrics, logs, traces — what each is good/bad at
  — *real story*: CloudWatch metrics + logs in this project (traces are the gap — name it honestly if asked)
- `[CORE]` What a good alert looks like: actionable, has an owner, avoids noise/flapping
  — *real story*: your alarm `evaluation_periods` and `treat_missing_data` choices
- `[CORE]` SLI vs SLO vs SLA — the precise distinction (indicator vs target vs contractual promise)
- `[GOOD TO KNOW]` Prometheus + Grafana model: pull-based scraping, PromQL, exporters
- `[GOOD TO KNOW]` Centralized logging (ELK/EFK stack, or CloudWatch Logs Insights) — structured vs unstructured logs
- `[GOOD TO KNOW]` Distributed tracing concept (a trace ID following a request across services) — X-Ray, Jaeger, OpenTelemetry as the vendor-neutral standard
- `[AWARENESS]` RED method (Rate, Errors, Duration) and USE method (Utilization, Saturation, Errors) as dashboard design frameworks

---

## 8. SRE Practices

- `[CORE]` Error budgets: the SLO defines how much unreliability is "allowed," and that budget is spent deliberately (ship faster) or conserved (freeze risky changes)
- `[CORE]` Incident severity levels, and what changes in process at each level
- `[CORE]` Blameless postmortems — why blame suppresses the honest reporting that prevents repeat incidents
  — *related story*: your own "challenges faced" doc is effectively a set of mini-postmortems — reframe them that way if asked
- `[CORE]` **MTTD / MTTR / MTBF** — Mean Time To Detect (how long until
  you *knew* something was wrong — the metric your alerting quality
  directly drives), Mean Time To Resolve (detection to fix), Mean Time
  Between Failures (how often incidents happen at all). Interviewers often
  ask which one a given change improves — e.g. better alarms improve MTTD,
  a better runbook improves MTTR, neither improves MTBF.
- `[GOOD TO KNOW]` The **"5 whys"** — a root-cause technique: keep asking
  "why did that happen" past the first, obvious answer until you hit the
  actual systemic cause instead of stopping at "the deploy broke it."
- `[GOOD TO KNOW]` Toil — repetitive manual work that doesn't scale with growth — and why reducing it is a stated SRE goal, not just "nice to automate"
- `[GOOD TO KNOW]` On-call structure: rotations, escalation policies, runbooks vs playbooks
- `[GOOD TO KNOW]` Capacity planning — using current trends to forecast when you'll run out of headroom (ties to your RDS connection-limit alarm)
- `[AWARENESS]` Chaos engineering (deliberately injecting failure to verify resilience assumptions, e.g. Chaos Monkey)
- `[AWARENESS]` The reliability-vs-velocity tension as the central SRE trade-off

---

## 9. Security (DevSecOps)

- `[CORE]` Shift-left security — catching issues at commit/PR time instead of in production
  — *real story*: `npm audit` + Trivy in your pipeline
- `[CORE]` Secrets management — never in code/git, short-lived over long-lived, rotation
  — *real story*: Secrets Manager, OIDC
- `[CORE]` Encryption in transit vs at rest, and what TLS actually buys you vs what it doesn't (your `rejectUnauthorized: false` discussion is exactly this nuance)
- `[GOOD TO KNOW]` SAST vs DAST vs SCA (static code analysis vs dynamic/runtime testing vs dependency/supply-chain scanning) — Trivy and `npm audit` are both SCA
- `[GOOD TO KNOW]` Container image scanning, base image minimization, non-root containers
- `[GOOD TO KNOW]` Principle of least privilege applied to IAM policies — scoped resources vs wildcards
  — *real story*: your GitHub Actions IAM policy, scoped to specific ECR repos/ECS services
- `[AWARENESS]` Compliance frameworks by name and rough purpose: SOC 2 (controls/trust), PCI-DSS (payment card data), HIPAA (health data), GDPR (EU personal data) — you don't need depth, just to recognize when a design choice would or wouldn't satisfy one
- `[AWARENESS]` Zero trust — "never trust by network location alone, verify every request" — same philosophy as your SG-to-SG chaining, one level up

---

## 10. Databases & Data

- `[CORE]` SQL vs NoSQL — what kind of access pattern favors each
- `[CORE]` Indexing basics — why they speed up reads and slow down writes
- `[CORE]` **ACID** (Atomicity, Consistency, Isolation, Durability) — what
  a transaction actually guarantees; a common follow-up is "what's a case
  where you *need* a transaction" (e.g. transferring money between two
  rows — both updates succeed or neither does).
- `[GOOD TO KNOW]` **Connection pooling** — why you don't open a fresh DB
  connection per request (connection setup is expensive, and the DB has a
  hard max-connections ceiling) — a pool of reusable, pre-opened
  connections shared across requests is the standard fix.
- `[GOOD TO KNOW]` Replication (read replicas) vs sharding (splitting by key) — different problems, don't conflate them
- `[GOOD TO KNOW]` Backup strategy: RPO (how much data loss is acceptable) vs RTO (how long until restored) — two different numbers interviewers like to separate
- `[GOOD TO KNOW]` Caching basics (Redis/Memcached) — cache-aside pattern, invalidation being "the hard part"
- `[AWARENESS]` CAP theorem — consistency vs availability trade-off under a network partition; know it exists and roughly what it constrains

---

## 11. System Design / Architecture (Junior Architect focus)

- `[CORE]` Horizontal vs vertical scaling, and statelessness as what makes horizontal scaling possible
- `[CORE]` Designing for failure: retries with backoff, timeouts, circuit breakers — and why naive retries can make an outage worse (retry storms)
- `[CORE]` Idempotency in API design — why it matters for safe retries (e.g. payment APIs)
- `[GOOD TO KNOW]` Microservices vs monolith — real trade-offs (deployment independence vs operational complexity), not just "microservices are modern"
- `[GOOD TO KNOW]` Event-driven architecture — queues/pub-sub decoupling producers from consumers, backpressure handling
- `[GOOD TO KNOW]` REST vs GraphQL vs gRPC — when each fits
- `[GOOD TO KNOW]` Rate limiting strategies (token bucket, sliding window) and why they protect downstream systems
- `[GOOD TO KNOW]` Architecture Decision Records (ADRs) — documenting *why* a decision was made, not just what — this entire `docs/` folder is effectively ADR-style thinking already
- `[AWARENESS]` Active-active vs active-passive multi-region, and the added complexity active-active brings (data consistency across regions)

---

## 12. Scripting, Git, and Tooling

- `[CORE]` Git: branching strategies, rebase vs merge (and why rebase rewrites history), resolving conflicts, `git bisect` for finding a regression
- `[CORE]` Git day-to-day commands beyond branch/merge: `git stash`
  (shelve uncommitted work temporarily), `git cherry-pick` (pull one
  specific commit onto another branch), tags (marking a release commit),
  and `git log`/`git blame` for history archaeology.
- `[CORE]` Bash scripting basics: variables, conditionals, loops, exit codes, piping
- `[CORE]` YAML and JSON fluency — not a "technology" so much as the format
  nearly everything in this doc is configured in (GitHub Actions, K8s
  manifests, Terraform's `.tfvars.json`, Docker Compose, OpenAPI specs) —
  specifically knowing YAML's indentation-is-structure gotcha and how it
  maps 1:1 to JSON conceptually.
- `[AWARENESS]` Git hooks (`pre-commit`, `pre-push`) — running a script
  automatically at a git lifecycle point, e.g. linting before a commit is
  allowed to land.
- `[GOOD TO KNOW]` Python for automation/tooling — even basic scripting fluency is commonly expected
- `[AWARENESS]` Go — not expected to write it, but worth recognizing that
  most of the cloud-native tooling you already use day-to-day (Kubernetes,
  Docker, Terraform itself and most of its providers, Prometheus) is
  written in Go, which is why so many SRE postings list it as a plus even
  at a junior level
- `[AWARENESS]` Basic data structures awareness (arrays/maps/sets, Big-O intuition) — rarely the focus at this level, but sometimes a warm-up question

---

## 13. Cost & FinOps Basics

- `[GOOD TO KNOW]` Rightsizing — matching instance/task size to actual observed load (ties to your RDS right-sizing answer; note Performance Insights is not enabled in this project, so say "I'd enable it")
- `[GOOD TO KNOW]` Tagging strategy for cost allocation by team/project/environment
- `[AWARENESS]` Reserved Instances / Savings Plans vs Spot — commitment-based discount vs interruptible discount
- `[AWARENESS]` Budget alerts / anomaly detection on cloud spend

---

## 13a. Certifications Worth Naming (Junior-Level Market Signal)

> Job postings for all four role flavors in this doc consistently name
> certifications as a differentiator at the junior level — not required,
> but worth knowing which one maps to which role so you can answer "any
> certs, or planning any?" with something specific instead of a blank look.

- `[GOOD TO KNOW]` **AWS Certified Solutions Architect – Associate** — the
  single most commonly requested cert across all four role flavors in this
  doc; broad coverage of exactly Section 3's territory (VPC, IAM, compute,
  storage, DB choice).
- `[GOOD TO KNOW]` **AWS Certified DevOps Engineer – Professional** — the
  natural next step once Associate-level is done, specifically CI/CD and
  operations-focused — maps closest to Sections 5/6/7 in this doc.
- `[AWARENESS]` **CKA (Certified Kubernetes Administrator)** / **CKAD**
  (Application Developer variant) — the credential that signals real K8s
  depth beyond the conceptual mapping in Section 15a.
- `[AWARENESS]` **HashiCorp Terraform Associate** — validates exactly the
  IaC fundamentals in Section 6.
- `[AWARENESS]` CompTIA Cloud+ — a vendor-neutral alternative sometimes
  listed for roles that don't want to commit to one cloud provider.

---

## 14. Behavioral & Scenario Questions (expect at least one or two)

- "Tell me about a production incident you were involved in — what happened, what did you do, what changed afterward?"
  — *you have several real answers in `challenges_faced.md` and `mock_qa.md` Section 9*
- "Describe a time you found a problem nobody asked you to look for."
  — *real story*: the security group / test-drift bugs caught during this very prep session
- "How do you decide between fixing something properly now vs shipping a known trade-off and coming back to it?"
  — *this project is full of named, deliberate trade-offs — good material*
- "Tell me about a time you disagreed with a technical decision."
- "How do you approach learning an unfamiliar tool or service under time pressure?"
- "How do you prioritize when everything feels urgent?"

---

## 15. Deep Dive — Closing the Three Named Gaps

> These three didn't have a real project story behind them. Rather than leave
> them as bare bullet points, here's enough depth to actually answer on, plus
> — where possible — a worked example using *this* project, so even the gaps
> turn into "here's how I'd extend what I built" answers instead of blank
> stares.

### 15a. Kubernetes — translating what you already know

You know ECS deeply. Almost every ECS concept has a direct Kubernetes
equivalent — the fastest way to answer a K8s question is to translate, out
loud, from what you already built.

| ECS concept (you know this) | Kubernetes equivalent |
| --- | --- |
| Task Definition | Pod spec (inside a Deployment) |
| Service (desired count, rolling update) | Deployment + ReplicaSet |
| ALB target group + health check | Service + Ingress, readiness probe |
| `/health` endpoint your ALB polls | the same endpoint, polled by a **readiness probe** instead |
| Task Execution Role (pulls secrets/image) | handled by kubelet + imagePullSecrets, no direct 1:1 but same purpose |
| ECS Secrets injection from Secrets Manager | a `Secret` object, or the AWS Secrets & Configuration Provider (ASCP) for the CSI driver |
| Application Auto Scaling (CPU-based) | Horizontal Pod Autoscaler (HPA) |
| awsvpc networking (one ENI per task) | each Pod gets its own cluster-internal IP, via CNI plugin |
| `aws ecs describe/render/deploy-task-definition` in your pipeline | `kubectl apply` of a new manifest, or a GitOps tool (ArgoCD) watching a git repo |

**Core objects to be able to define in one sentence each, cold:**

- **Pod** — the smallest deployable unit; one or more containers that share network/storage.
- **Deployment** — manages a set of identical Pods, handles rolling updates and self-healing.
- **Service** — a stable network identity/IP in front of a changing set of Pods (Pods' own IPs are ephemeral).
- **Ingress** — L7 routing rules (path/host-based), the rough equivalent of your ALB listener rules.
- **ConfigMap / Secret** — non-sensitive and sensitive config injected into Pods, same role as your ECS environment variables and `secrets` block.
- **Namespace** — a logical partition of a cluster (multi-tenancy, resource quotas).

**Liveness vs. readiness vs. startup probes** (a very common follow-up):

- **Readiness** — "can this Pod take traffic right now?" Fails → removed from the Service's load-balancing rotation, but the Pod is *not* killed. This is the direct equivalent of your ALB health check.
- **Liveness** — "is this Pod still alive at all?" Fails → kubelet kills and restarts the container.
- **Startup** — a grace period for slow-starting apps before liveness checks even begin, so a legitimately slow boot (like your schema-init IIFE) doesn't get killed mid-startup.

**If asked "have you used Kubernetes?" — the honest, strong answer:**
> "Not hands-on in production — this project uses ECS Fargate, which I chose
> deliberately over EKS because the operational overhead of running Kubernetes
> wasn't justified for a two-service app. But the concepts map directly: my
> ALB health check is functionally a readiness probe, my ECS service's desired
> count and rolling update is what a Deployment gives you, and my Secrets
> Manager injection is what a Secret object or the ASCP CSI driver would do in
> K8s. I'd be comfortable picking it up quickly because the mental model
> transfers — the syntax and tooling is what I'd need to ramp on."

### 15b. Distributed Tracing — what it is, and how you'd add it here

**What a trace actually is:** one user request, followed across every service
hop it touches, assembled from **spans** — one span per hop/operation — each
with a start time, duration, and a **parent span ID** linking it back to the
span that called it. The **trace ID** is the thread that ties all spans from
one request together. Logs tell you *what* happened in one place; metrics tell
you *how much/how often*; a trace tells you **where the time actually went**
across a multi-hop request — which log lines and dashboards can't reconstruct
on their own once more than a couple of services are involved.

**Why this project doesn't have it, honestly:** there are only two hops —
ALB → backend → RDS — so a trace would mostly restate what the ALB latency
widget and the backend's request logger already show. Tracing earns its keep
once you have enough services that "which hop is actually slow" stops being
obvious from logs alone.

**Concretely how you'd add it, if asked "how would you add this":**

1. Enable **X-Ray** (AWS-native, fits this stack directly) — turn on
   `enable_tracing` / X-Ray on the ALB and ECS task definitions.
2. Add the `aws-xray-sdk` package to the Node backend, wrap the Express app
   with its middleware, and instrument the `pg` pool calls so the DB query
   itself shows up as its own span, not just "backend took 400ms."
3. Each request would then show: ALB → backend span → Postgres query span,
   with exact durations for each — so "is it the network, the app, or the
   query?" becomes a two-second look instead of a guess.
4. OpenTelemetry is the vendor-neutral standard if you wanted to avoid being
   locked into X-Ray specifically — same concepts (traces/spans/trace
   context propagation), pluggable backend.

**One-liner if pushed:** *"I have metrics and centralized logs today, which
cover the two-hop case I actually have. Tracing is the next thing I'd add the
moment a third service enters the picture, and X-Ray is the natural fit since
I'm already all-in on AWS-native observability."*

### 15c. SRE Vocabulary — SLI / SLO / SLA / Error Budget / Toil, worked against this project

These terms describe things you're *already doing* with your CloudWatch
alarms and dashboards — you just haven't named them this way yet. Here's the
exact vocabulary, plus what it would look like applied to Octa Byte.

- **SLI (Service Level Indicator)** — a specific, measured number. Example
  for this project: *"% of ALB requests per month that do NOT return a 5XX."*
  Your `alb_5xx` alarm is already watching the raw ingredient this SLI is made
  from — it's just a count right now, not yet expressed as a ratio over a
  rolling window.
- **SLO (Service Level Objective)** — the internal target for that SLI.
  Example: *"99.5% of requests succeed, measured over a trailing 30 days."*
- **SLA (Service Level Agreement)** — the external, often contractual,
  promise to a customer — usually looser than your internal SLO, with real
  consequences (credits, penalties) if missed. You'd always set the SLO
  stricter than the SLA so you breach your own internal target before you
  ever breach the customer-facing one.
- **Error budget** — `100% - SLO` = how much failure you're *allowed*. At a
  99.5% SLO, your error budget is 0.5%. Worked example: if the ALB serves 1
  million requests this month, you're allowed 5,000 failed ones before you've
  spent the whole budget. Spend it deliberately — ship a riskier change,
  knowing you have room — or conserve it — freeze risky deploys because
  you're close to burning through it. This is the exact mechanism that turns
  "reliability" from a vague feeling into a number you can make shipping
  decisions against.
- **Burn rate** — how *fast* you're consuming that error budget. A slow burn
  (you'll exhaust the budget in 20 days) can wait for business hours; a fast
  burn (you'll exhaust it in 2 hours) pages someone immediately. This is why
  mature alerting is usually budget-burn-rate based, not just a flat
  threshold like "5XX count > 10."
- **Toil** — manual, repetitive operational work that doesn't scale as the
  system grows, and doesn't make the system better by being done. From your
  own `challenges_faced.md`: forcing an **empty commit to re-trigger the
  pipeline** after the Terraform/CI race condition is toil — a manual,
  repeatable workaround for a process gap. The **manual production approval
  gate**, by contrast, is *not* toil — it's a deliberate control, not
  accidental manual work. Knowing the difference between "manual because we
  haven't automated it yet" and "manual on purpose, as a safety control" is
  exactly the distinction interviewers are listening for.

**If asked "do you have SLOs defined for this project?" — honest, forward-looking answer:**
> "Not formally — this is a single-app assignment, not a system with customer
> SLAs attached. But if I were to define one: my ALB 5XX alarm and latency
> widget already measure the two SLIs I'd use — request success rate and
> p-something latency. An SLO might be 99.5% success and, say, 95% of
> requests under 500ms over a rolling 30 days. CloudWatch alarms today are
> threshold-based, not budget-based, so the next step to make this a real
> SRE-style setup would be a scheduled job computing burn rate against that
> rolling window, rather than alerting on a flat count."

---

## 16. Trends & Emerging Technologies (2025–2026) — Cross-Role Deep Dive

> This section is deliberately **not** tied to the Octa Byte project — it's
> what's actually moving in the DevOps / SRE / Cloud / Junior Solutions
> Architect job market right now, broken into named sub-topics so you can
> spot which ones you've never heard of versus which you just haven't
> labeled yet. Same priority-tag convention as above.

### 16a. Platform Engineering & Internal Developer Platforms (IDPs)

- `[CORE]` **Platform Engineering as a discipline** — treating internal
  infrastructure as a *product* for other developers, with the platform
  team as the "vendor." This is the industry's answer to "DevOps got too
  hard for every team to own end-to-end."
- `[CORE]` **Internal Developer Platform (IDP)** — a self-service layer
  (golden paths, templates, a catalog) that lets app developers provision
  a database, a new service, or an environment without filing a ticket to
  the platform team.
- `[GOOD TO KNOW]` **Backstage** (Spotify's open-sourced IDP framework) —
  the dominant open-source tool in this space: software catalog, templates,
  TechDocs, plugin ecosystem.
- `[GOOD TO KNOW]` **Golden paths / paved roads** — the one blessed,
  supported way to deploy a typical service, vs letting every team invent
  its own pipeline from scratch.
- `[AWARENESS]` Commercial IDP players by name: Humanitec, Port, Cortex —
  know they exist as "Backstage alternatives/add-ons," not deep feature
  comparisons.

### 16b. GitOps & Progressive Delivery

- `[CORE]` **Progressive delivery** — the generalization of canary/blue-green:
  shipping to a small slice of traffic/users first, watching real signals,
  then widening — as opposed to an all-or-nothing deploy.
- `[GOOD TO KNOW]` **ArgoCD vs Flux** — the two dominant GitOps controllers
  for Kubernetes; both reconcile cluster state to match a git repo, differ
  mainly in UI/ecosystem maturity (Argo) vs simplicity/Flux CD's tighter
  Flagger integration.
- `[GOOD TO KNOW]` **Argo Rollouts / Flagger** — automate canary analysis
  itself: shift 5% → 25% → 50% → 100% traffic while watching an error-rate
  or latency metric, auto-rolling-back on regression without a human
  babysitting each step.
- `[AWARENESS]` **Feature flag platforms** (LaunchDarkly, Unleash,
  OpenFeature as the vendor-neutral API) as the mechanism that decouples
  *deploy* from *release* — code ships dark, flag flips it on later.

### 16c. eBPF-Based Observability & Security

- `[GOOD TO KNOW]` **eBPF (extended Berkeley Packet Filter)** — lets you run
  sandboxed programs inside the Linux kernel without changing kernel source
  or loading a module. It's the foundation under a wave of newer
  observability and networking tools because it can see every syscall,
  packet, and process with near-zero overhead, at a layer no app-level agent
  can reach.
- `[GOOD TO KNOW]` **Cilium** — eBPF-based CNI (container networking) that
  also does L3–L7 network policy and service mesh *without sidecars*.
- `[AWARENESS]` **Pixie / Parca / Falco** — eBPF-powered tools for
  auto-instrumented observability (Pixie), continuous profiling (Parca),
  and runtime security/threat detection (Falco) — know the one-line pitch
  for each, not internals.

### 16d. Service Mesh Evolution

- `[GOOD TO KNOW]` **What a service mesh solves**: mTLS between services,
  retries/timeouts/circuit-breaking as infra config instead of
  per-app code, and L7 traffic shaping — all without touching application
  code.
- `[GOOD TO KNOW]` **Sidecar fatigue** — the well-known cost of the classic
  Istio/Linkerd model: one extra proxy container per Pod, doubling resource
  overhead and adding latency.
- `[AWARENESS]` **"Ambient mesh"** (Istio's sidecar-less mode, built on a
  shared per-node proxy) and **Cilium's mesh mode** (eBPF instead of
  proxies) — the current industry direction is explicitly *away* from
  "one sidecar per pod" toward lighter-weight models.

### 16e. Software Supply Chain Security

- `[CORE]` **SBOM (Software Bill of Materials)** — a manifest of every
  dependency (and transitive dependency) in a build, in a standard format
  (SPDX or CycloneDX) — the direct extension of the `npm audit`/Trivy
  story you already have, just formalized as an artifact you publish
  alongside the build.
- `[GOOD TO KNOW]` **SLSA (Supply-chain Levels for Software Artifacts)** —
  a maturity ladder (levels 1–4) for how tamper-resistant your build
  pipeline is — e.g., are builds reproducible, is provenance signed, can
  a single compromised laptop poison a release.
- `[GOOD TO KNOW]` **Sigstore / cosign** — free, keyless signing and
  verification for container images and artifacts, so a cluster can refuse
  to run an image that isn't signed by your CI.
- `[GOOD TO KNOW]` **Policy-as-code admission control**: **OPA/Gatekeeper**
  and **Kyverno** — Kubernetes-native policy engines that block a deploy at
  admission time (e.g., "reject any Pod running as root" or "reject any
  unsigned image") — the cluster-level sibling of the Terraform
  policy-as-code idea already in Section 6.
- `[AWARENESS]` The real-world driving incidents behind this trend:
  SolarWinds and the `xz`/`log4j` style dependency-compromise events — know
  the *shape* of the problem (trusted-looking dependency turns out to be
  compromised) even if not the specific CVE details.

### 16f. AI in DevOps/SRE — AIOps, LLMOps, and Agentic Operations

- `[CORE]` **AIOps** — using ML/anomaly-detection on metrics/logs to surface
  "this looks wrong" before a static threshold alarm would fire, and to
  correlate multiple alerts into one incident instead of paging five times
  for one root cause.
- `[GOOD TO KNOW]` **LLM-assisted incident response** — tools that draft an
  incident summary, suggest a likely root cause from past postmortems, or
  generate a first-pass runbook step from an error signature — positioned
  as *augmenting* the on-call engineer, not replacing the judgment call.
- `[GOOD TO KNOW]` **LLMOps** — the emerging discipline of operating LLM
  workloads themselves in production: prompt/version management, token-cost
  monitoring, latency SLOs for inference, eval pipelines for regressions —
  effectively "MLOps, but for LLM-shaped workloads" and increasingly its
  own line item in a platform team's remit.
- `[AWARENESS]` **Agentic pipelines** — CI/CD or on-call tooling where an
  LLM agent can take bounded actions (open a PR, restart a known-safe
  service, triage a ticket) under guardrails, rather than just summarizing
  for a human — still early and usually scoped very narrowly in production
  today.

### 16g. FinOps Maturity

- `[GOOD TO KNOW]` **FinOps as a practice, not just "watch the bill"** —
  a cross-functional discipline (finance + engineering + product) with its
  own maturity phases: *Inform* (visibility/tagging) → *Optimize*
  (rightsizing, commitments) → *Operate* (continuous governance, cost as a
  first-class metric in the sprint, not an annual review).
- `[GOOD TO KNOW]` **Unit economics** — cost per customer/request/transaction,
  not just total spend — the metric that actually matters once total spend
  alone stops being informative at scale.
- `[AWARENESS]` **Kubecost** / cloud-native cost allocation tooling — attributing
  shared cluster cost down to namespace/team/deployment, the K8s-world
  equivalent of the tagging-for-cost-allocation idea in Section 13.

### 16h. Infrastructure as Code — What's Shifting

- `[GOOD TO KNOW]` **OpenTofu** — the Linux Foundation's open-source fork of
  Terraform, created after HashiCorp's 2023 license change (BSL) away from
  pure open source; functionally near-identical today, but know *why* it
  exists if asked — it's a licensing story, not a technical fork.
- `[GOOD TO KNOW]` **Crossplane** — manages cloud infrastructure via
  Kubernetes CRDs/control loops instead of a separate `plan`/`apply` tool —
  pitched as "one control plane for apps *and* infra," popular in
  platform-engineering/IDP setups specifically because it fits the K8s-native
  reconciliation model.
- `[AWARENESS]` **Ephemeral/preview environments** — spinning up a full
  short-lived environment per PR (via IaC + GitOps) for integration testing,
  then tearing it down — increasingly standard in mature CI/CD setups.

### 16i. Zero Trust & Cloud Security Posture Management

- `[GOOD TO KNOW]` **CSPM (Cloud Security Posture Management)** —
  continuous automated scanning of your actual cloud config against
  best-practice baselines (an open S3 bucket, an overly-permissive security
  group, an unencrypted volume) — AWS Security Hub / GuardDuty, or
  third-party (Wiz, Prisma Cloud) are the names that come up.
- `[GOOD TO KNOW]` **Zero Trust Architecture (ZTA)**, concretely —
  per-request identity-based verification instead of "inside the VPC =
  trusted": mTLS between every service, short-lived credentials everywhere,
  explicit allow-lists instead of network-perimeter trust. This is the same
  philosophy as SG-to-SG chaining, formalized and pushed further (NIST
  SP 800-207 is the reference document if a name is asked for).
- `[AWARENESS]` **Identity as the new perimeter** — the one-line summary of
  why IAM/identity work has absorbed so much of what used to be "network
  security" as workloads spread across more clouds and SaaS.

### 16j. Serverless & Edge Computing Evolution

- `[GOOD TO KNOW]` **Edge functions** (Cloudflare Workers, Lambda@Edge,
  Fastly Compute) — running small bits of request-handling logic at a CDN
  point-of-presence close to the user, instead of round-tripping to a
  region — common use: auth checks, A/B routing, header rewriting, before
  the request ever reaches origin.
- `[GOOD TO KNOW]` **Lambda SnapStart** and similar cold-start mitigations —
  snapshotting an initialized execution environment so a cold start skips
  re-running init code — the current industry answer to "serverless cold
  starts are a real latency problem for latency-sensitive paths."
- `[AWARENESS]` **WebAssembly (WASM) on the server/edge** — a lighter-weight,
  faster-starting sandbox than a container for short-lived compute; still
  early for general backend workloads but the clear direction for edge
  compute specifically (Fermyon, Fastly's WASM runtime).

### 16k. Chaos Engineering & Resilience Testing

- `[GOOD TO KNOW]` **Game days** — a scheduled, planned exercise where a team
  deliberately simulates a failure (kill a node, inject latency, cut a
  dependency) during business hours with everyone watching, specifically to
  test the *response process*, not just the system.
- `[AWARENESS]` Tooling by name: **Gremlin** (commercial chaos-as-a-service),
  **LitmusChaos / Chaos Mesh** (Kubernetes-native, open source) — know they
  exist as the practical tools behind "chaos engineering," already named at
  the concept level in Section 8.

### 16l. Sustainability / GreenOps

- `[AWARENESS]` **Carbon-aware computing** — shifting batch/non-urgent
  workloads to run when/where the electricity grid is greener (more
  renewable mix), or to lower-carbon regions — an emerging sixth pillar
  alongside the five classic Well-Architected pillars (Sustainability was
  formally added as AWS's sixth pillar).
- `[AWARENESS]` Cloud providers now expose **carbon footprint
  tools** (AWS Customer Carbon Footprint Tool, GCP Carbon Footprint) — know
  that these exist as a reporting layer, not that you need to act on them yet.

### 16m. Data Platform Trends Relevant to This Role Family

- `[GOOD TO KNOW]` **Vector databases** (pgvector on Postgres, Pinecone,
  OpenSearch's vector support) — storing embeddings for similarity search,
  now a standard building block behind any RAG/LLM-search feature — worth
  knowing *why* a team would bolt one onto an existing Postgres (pgvector)
  rather than stand up a new dedicated store.
- `[AWARENESS]` **Serverless/auto-scaling databases** (Aurora Serverless v2,
  DynamoDB on-demand) — capacity that scales with load automatically instead
  of being provisioned for peak — directly relevant if asked "how would you
  avoid manually resizing this RDS instance as traffic grows."

---

## How to use this against the other docs in this folder

This file is the **map**. The other files are the **depth** you already have on
the subset of this map your project actually touches — VPC/subnetting,
security groups, IAM/OIDC, Secrets Manager, ECS/Fargate, ALB routing, RDS,
Terraform state/locking, CI/CD with GitHub Actions, and basic CloudWatch
observability. That's a genuinely large slice of this list already backed by
a real, debugged, working system — lean on those stories whenever a question
lands in that territory.

The three gaps that had no project story — **Kubernetes**, **distributed
tracing**, and **SRE vocabulary** (SLI/SLO/error budgets/toil) — now have
Section 15 above: translation tables, worked examples against this exact
project, and a ready one-liner for each if asked "have you done this?" They
won't read as deep hands-on experience, and you shouldn't claim they are —
but they'll read as someone who understands the concepts cold and can reason
about how to apply them, which is the right bar for a junior-level role.
