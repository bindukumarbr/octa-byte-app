# Octa Byte AI — Full-Stack Application & AWS Infrastructure

This repository contains the full-stack application code and the declarative Terraform infrastructure for the Octa Byte AI assignment. It follows modern AWS DevOps best practices for security, scalability, and automated deployments.

---

## Architecture Overview

The system is deployed on AWS using a highly secure, serverless, three-tier architecture:

1. **Frontend:** React + Vite, containerized and running on AWS Fargate.
2. **Backend:** Node.js Express API, containerized and running on AWS Fargate.
3. **Database:** Amazon RDS PostgreSQL, running in an isolated private subnet.

### Architectural Decisions & Rationale

- **Serverless Compute (ECS Fargate vs EC2):**
  I chose Fargate for container orchestration to achieve a "Zero-Ops" compute layer. By removing EC2 instances, there is no underlying OS to patch, no instances to monitor, and no capacity planning required. Scaling is handled seamlessly at the container level.
- **Three-Tier Subnet Isolation (Network Security):**
  I implemented a strict network topology. The Application Load Balancer sits in the **Public Subnet** (internet-facing). The ECS Fargate containers sit in the **Private Subnet** (can reach the internet via NAT Gateway for image pulls, but cannot be reached directly). The RDS Database sits in an **Isolated Subnet** (no NAT, no Internet Gateway) making it physically impossible to route to the database from the public internet.
- **ALB Consolidation (Cost Optimization):**
  Rather than provisioning two separate load balancers for the frontend and backend, I consolidated both services behind a single ALB. Path-based routing forwards traffic hitting `/api/*` to the backend target group, and all other traffic to the frontend. This cuts load balancer costs in half.
- **State Management (S3 + DynamoDB):**
  Terraform state is stored remotely in an S3 bucket with versioning enabled, ensuring state files are never lost or corrupted on local machines. DynamoDB is used for state locking, which safely prevents concurrent pipeline executions from corrupting the infrastructure state.
- **Centralized Monitoring (CloudWatch):**
  Instead of managing custom ELK/Prometheus stacks, all ECS container logs and ALB access logs stream directly to CloudWatch. I built custom Dashboards and Alarms within Terraform to immediately trigger alerts if CPU spikes or if the application throws 5XX errors.

---

## Security Best Practices

1. **Least-Privilege Security Groups:**
   - The ALB is the ONLY resource exposed to the internet (Port 80/443).
   - The ECS containers only accept inbound traffic originating strictly from the ALB security group.
   - The RDS database only accepts inbound traffic originating strictly from the ECS security group.
2. **AWS Secrets Manager (Secret Management):** I have utilized the `manage_master_user_password = true` flag in Terraform for RDS. Terraform never outputs the DB password to the state file; instead, AWS Secrets Manager automatically generates, encrypts, and periodically rotates the database credentials.
3. **OIDC Authentication for CI/CD:** I do NOT store long-lived AWS Access Keys in GitHub Secrets. I configured an OpenID Connect (OIDC) trust relationship. GitHub Actions requests a temporary, short-lived JWT token to deploy to AWS, ensuring zero risk of credential leaks if the repository is ever compromised.

---

## Cost Optimization Measures

- **Fargate Spot (Optional):** The ECS configuration allows easy migration to Fargate Spot for non-production environments to save up to 70% on compute costs.
- **Burstable RDS Instances:** The database utilizes `db.t3.micro` instances, which are highly cost-effective for spiky, unpredictable workloads like testing and staging.

---

## CI/CD Pipeline (GitHub Actions)

The pipeline is defined in `.github/workflows/deploy.yml` and enforces the following flow:

1. **Test Phase (On PR):** Runs Jest backend tests.
2. **Build Phase (On Merge):** Builds Docker images, tags them with the exact Git SHA for traceability, and pushes to Amazon ECR.
3. **Security Scan:** Uses Trivy to scan the container images for HIGH/CRITICAL vulnerabilities. If a CVE is found, the build fails and never deploys.
4. **Staging Deploy:** Auto-deploys to the staging ECS cluster.
5. **Production Gate:** Pauses execution and waits for approval via GitHub Environments before deploying to production.
6. **Alerting:** Sends a Slack webhook notification upon any failure.

---

## How to Deploy the Infrastructure

**Prerequisites:**

- AWS CLI installed and configured.
- Terraform `>= 1.5.0` installed.

**Steps:**

1. Navigate to the production environment directory:
   ```bash
   cd terraform/environments/prod
   ```
2. Initialize Terraform (downloads providers and configures S3 backend):
   ```bash
   terraform init
   ```
3. Preview the infrastructure changes:
   ```bash
   terraform plan
   ```
4. Apply the infrastructure:
   ```bash
   terraform apply
   ```
5. Once applied, Terraform will output the `alb_dns_name` (your live website URL).
