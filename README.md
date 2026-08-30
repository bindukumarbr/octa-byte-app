# Octa Byte AI. Stack Application and AWS Infrastructure

This repository has the full-stack application code and the declarative Terraform infrastructure for the Octa Byte AI assignment. It uses AWS DevOps best practices for security, scalability and automated deployments.

---

## Architecture Overview

The system is on AWS using a secure serverless three-tier architecture:

1. **Frontend:**. Vite, containerized and on AWS Fargate.

2. **Backend:** Node.js Express API, containerized and on AWS Fargate.

3. **Database:** Amazon RDS PostgreSQL, on a private subnet.

### Architectural Decisions and Reasoning

- **Serverless Compute (ECS Fargate versus EC2):**

Fargate was picked for container orchestration to get a "Zero-Ops" compute layer. By not using EC2 instances there is no underlying OS to fix no instances to check and no capacity planning needed. Scaling happens automatically at the container level.

- **Three-Tier Subnet Isolation (Network Security):**

A strict network setup is used. The Application Load Balancer is in the ** Subnet** (internet-facing). The ECS Fargate containers are in the ** Subnet** (can get to the internet through NAT Gateway for image pulls but cannot be accessed directly). The RDS Database is in an ** Subnet** (no NAT, no Internet Gateway) making it impossible to reach the database from the public internet.

- **ALB Consolidation (Cost Saving):**

of having two separate load balancers for the frontend and backend Both services are behind a single ALB. Path-based routing sends traffic hitting `/api/*` to the backend target group and all other traffic to the frontend. This reduces load balancer costs by half.

- **State Management (S3 and DynamoDB):**

Terraform state is kept remotely in an S3 bucket with versioning so state files are never lost or broken on machines. DynamoDB is used for state locking, which safely stops pipeline executions from breaking the infrastructure state.

- **Centralized Monitoring (CloudWatch):**

of managing custom ELK/Prometheus stacks, all ECS container logs and ALB access logs go directly to CloudWatch. Custom Dashboards and Alarms are made within Terraform to immediately alert if CPU spikes or if the application has 5XX errors.

---

## Security Best Practices

1. **Least-Privilege Security Groups:**

The ALB is the resource open to the internet (Port 80/443).

The ECS containers only allow traffic from the ALB security group.

The RDS database only allows inbound traffic from the ECS security group.

2. **AWS Secrets Manager (Secret Management):** The `manage_master_user_password = true` flag is used in Terraform for RDS. Terraform never shows the DB password in the state file; instead AWS Secrets Manager creates, encrypts. Regularly changes the database credentials.

3. **OIDC Authentication for CI/CD:** Long-lived AWS Access Keys are not in GitHub Secrets. Instead a Connect (OIDC) trust relationship is set up. GitHub Actions gets a short-lived JWT token to deploy to AWS ensuring no risk of credential leaks if the repository is ever compromised.

---

## Cost Saving Strategies

- **Fargate Spot (Optional):** The ECS setup allows a move to Fargate Spot for -production environments to save up to 70% on compute costs.

- **Burstable RDS Instances:** The database uses `db.t3.micro` instances, which're very cost-effective for spiky unpredictable workloads like testing and staging.

---

## CI/CD Pipeline (GitHub Actions)

The pipeline is in `.github/workflows/deploy.yml`. Has the following steps:

1. **Test Phase (On PR):** Runs Jest backend tests.

2. **Build Phase (On Merge):** Builds Docker images tags them with the Git SHA for traceability and pushes to Amazon ECR.

3. **Security Scan:** Uses Trivy to check container images for HIGH/CRITICAL vulnerabilities. If a CVE is found, the build. Does not deploy.

4. **Staging Deploy:** Auto-deploys to the staging ECS cluster.

5. **Production Gate:**. Waits for approval via GitHub Environments, before deploying to production.

6. **Alerting:** Sends a Slack webhook notification if there is any failure.

---

## How to Deploy the Infrastructure

**Requirements:**

- AWS CLI. Set up.

- Terraform `>= 1.5.0` installed.

**Steps:**

1. Go to the production environment folder:

```bash

cd terraform/environments/prod

```

2. Start Terraform (downloads providers and sets up S3 backend):

```bash

terraform init

```

3. See what changes will happen:

```bash

terraform plan

```

4. Apply the changes:

```bash

terraform apply

```

5. After applying Terraform will show the `alb_dns_name` (your live website URL).
