# INTERVIEW NOTE: This single file provisions the entire AWS
# infrastructure for the production environment using Terraform
# registry modules. Each "module" block calls a pre-built,
# community-maintained set of AWS resources.
#
# WHY modules instead of raw aws_* resources:
# Writing a VPC from scratch means manually creating aws_vpc,
# aws_subnet (x6), aws_internet_gateway, aws_route_table (x3),
# aws_route_table_association (x6), aws_nat_gateway, aws_eip...
# That is 20+ resources with subtle wiring that is easy to get wrong.
# The terraform-aws-modules/vpc module encodes AWS best practices
# and is reviewed by thousands of engineers. Knowing WHEN to reach
# for a vetted module vs hand-rolling is itself a senior judgement call.

# WHY these three data sources (not hardcoded values):
# Each one looks up a fact from the AWS account/region Terraform is
# actually running against, instead of us typing it in. That means this
# exact code would still work unchanged against a different AWS account
# or a different region — nothing below is tied to "this one account."
#
# aws_region.current: the region the provider is configured for.
# USE CASE: interpolated into ARNs below (e.g. the ECS service ARNs in
# the GitHub Actions IAM policy) so the region never has to be typed in.
data "aws_region" "current" {}

# aws_caller_identity.current: identity of whoever/whatever is running
# Terraform right now — gives us .account_id, .arn, .user_id.
# USE CASE: .account_id is interpolated into every ARN we build by hand
# further down (ECS service ARNs, the four IAM PassRole resource ARNs),
# so the 12-digit account number is never hardcoded anywhere in this file.
data "aws_caller_identity" "current" {}

# aws_availability_zones.available: every AZ in this region that is
# actually usable right now (state = "available" filters out any AZ
# that's deprecated or not opted into for this account).
# USE CASE: feeds local.azs below via slice(..., 0, 2) — we dynamically
# grab the first two real AZs instead of hardcoding "us-east-1a/1b",
# so the same code deploys cleanly in any region.
data "aws_availability_zones" "available" { state = "available" }

locals {
  name     = "${var.project_name}-${var.environment}"
  vpc_cidr = var.vpc_cidr
  # Dynamically pick the first 2 AZs available in the region.
  # WHY 2 AZs: A single-AZ design has no answer to "what happens if
  # that AZ goes down?" Two AZs is the minimum viable definition of
  # High Availability. Three AZs would triple NAT Gateway costs with
  # marginal resilience gain for this workload.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# 1. VPC — Three-Tier Subnet Architecture

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.2"

  name = "${local.name}-vpc"
  cidr = local.vpc_cidr
  azs  = local.azs

  # WHY three distinct subnet tiers (not two):
  # A flat public/private design puts the DB in the same private subnet
  # as compute. One security group misconfiguration can then expose the DB.
  # Three tiers require TWO separate mistakes before the DB is exposed.
  #
  # public_subnets:   ALB only. The ONLY tier with an internet gateway route.
  # private_subnets:  ECS tasks. Can reach internet via NAT (to pull images),
  #                   but nothing can reach IN from the internet.
  # database_subnets: RDS only. No internet gateway. No NAT route.
  #                   Physically impossible to reach from outside the VPC.
  #
  # HOW the CIDR math works — cidrsubnet(prefix, newbits, netnum):
  #   prefix:  the base block to carve up      -> local.vpc_cidr = "10.0.0.0/16"
  #   newbits: how many bits to extend it by    -> 8  (so /16 becomes /24,
  #            i.e. each subnet gets 256 IPs instead of 65,536)
  #   netnum:  WHICH /24 block to return, 0-indexed within that /16
  #
  # k is the AZ's index (0, 1, ...) from the `for k, v in local.azs` loop.
  # Each tier is offset by a fixed block of 2 so the three tiers never
  # collide, for exactly 2 AZs:
  #   public_subnets   -> k + 0  -> AZ0 = 10.0.0.0/24, AZ1 = 10.0.1.0/24
  #   private_subnets  -> k + 2  -> AZ0 = 10.0.2.0/24, AZ1 = 10.0.3.0/24
  #   database_subnets -> k + 4  -> AZ0 = 10.0.4.0/24, AZ1 = 10.0.5.0/24
  # (verified with `terraform console`)
  #
  # CROSS-QUESTION: "What happens if you add a third AZ?"
  # This offset scheme is only collision-free because local.azs is
  # hardcoded to slice(..., 0, 2) — exactly 2 AZs. Bump that slice to 3
  # without changing these offsets and public's 3rd subnet (k=2 -> netnum
  # 2 -> 10.0.2.0/24) collides with private's 1st subnet (k=0+2 -> netnum
  # 2 -> also 10.0.2.0/24) — confirmed by evaluating both expressions with
  # 3 AZs. The safe fix for a variable AZ count is to offset each tier by
  # a fixed ceiling (e.g. k + max_azs, k + 2*max_azs) instead of a literal
  # +2/+4, so growing the AZ count can never walk into the next tier's range.
  public_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 2)]
  database_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 4)]

  # WHY NAT Gateway:
  # ECS tasks in private subnets need OUTBOUND internet access to:
  #   1. Pull Docker images from ECR
  #   2. Call AWS APIs (Secrets Manager, CloudWatch)
  # A NAT Gateway allows outbound connections while keeping the subnet
  # unreachable from inbound internet traffic.
  #
  # single_nat_gateway = true: one NAT serves both AZs.
  # Cost trade-off: two NAT gateways (~$64/month) give true AZ-level
  # resilience but doubles cost. Single NAT is fine for this assignment.
  enable_nat_gateway = true
  single_nat_gateway = true

  create_database_subnet_group = true
}

# 2. Security Groups — SG-to-SG Chaining

# WHY SG-to-SG references instead of CIDR ranges:
# A CIDR rule like "allow 10.0.0.0/16" allows ANYTHING in the VPC
# to reach the target — including resources you add later that should
# not have that access. An SG reference says "only traffic from THIS
# specific group of resources", regardless of their IP addresses.
# This is critical for ECS Fargate: tasks get new ENIs (and new IPs)
# on EVERY deployment. A hardcoded IP or CIDR would break instantly.
#
# CROSS-QUESTION: "Why not just allow the private subnet CIDR to RDS?"
# Because anything else ever placed in that subnet (a Lambda, a bastion)
# would automatically inherit database access. SG-to-SG scopes access
# to the specific resource type, not its network location.

module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0"

  name   = "${local.name}-alb-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = {
    # The ALB is the ONLY resource that accepts inbound internet traffic.
    # Port 80 from 0.0.0.0/0 (the public internet).
    # In a production HTTPS setup, you would add port 443 here and
    # attach an ACM TLS certificate to the ALB listener.
    http_allow = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow HTTP from internet"
    }
  }

  egress_rules = {
    allow_all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound"
    }
  }
}

# WHY one security group PER ECS service (not one shared by both):
# The RDS security group below trusts a specific source security group.
# If the frontend (static Nginx) and backend (Node API) shared one group,
# that trust would also cover the frontend tasks, so a compromised web
# container could connect straight to the database on 5432. Separate groups
# keep the chain tight: only the BACKEND group is ever allowed to reach RDS.
# It also means each service only exposes the one port it actually serves.
module "ecs_frontend_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name   = "${local.name}-ecs-frontend-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = {
    # referenced_security_group_id = module.alb_sg.id
    # This is the SG-to-SG chain. Only traffic originating from the
    # ALB security group can reach the frontend containers. Not "any
    # private IP" — specifically the ALB, and only on Nginx's port.
    from_alb = {
      from_port                    = 80
      to_port                      = 80
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb_sg.id
      description                  = "Allow frontend traffic from ALB"
    }
  }

  egress_rules = {
    egress_all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound (for ECR pulls and CloudWatch Logs)"
    }
  }
}

module "ecs_backend_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name   = "${local.name}-ecs-backend-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = {
    # Same SG-to-SG idea: only the ALB may reach the API, and only on 4000.
    from_alb = {
      from_port                    = 4000
      to_port                      = 4000
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb_sg.id
      description                  = "Allow backend traffic from ALB"
    }
  }

  egress_rules = {
    egress_all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound (for ECR pulls, Secrets Manager, CloudWatch)"
    }
  }
}

module "rds_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name   = "${local.name}-rds-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = {
    # RDS only accepts connections from the BACKEND ECS tasks — not from the
    # frontend tasks, not from the ALB, not from the internet.
    # The chain is: Internet -> ALB SG -> backend SG -> RDS SG
    # (the frontend SG branches off the ALB but has no path to RDS).
    postgres_from_backend = {
      from_port                    = 5432
      to_port                      = 5432
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.ecs_backend_sg.id
      description                  = "Allow PostgreSQL from backend ECS tasks only"
    }
  }
}

# 3. Application Load Balancer — Path-Based Routing

# WHY one ALB instead of two (one for frontend, one for backend):
# Two ALBs = two DNS names. The frontend React app would need to know
# the backend ALB hostname, which is environment-specific and changes.
# This creates CORS complexity and doubles ALB costs (~$16/month each).
# One ALB + path-based routing = one DNS name, zero CORS issues,
# the ALB itself handles the separation.
#
# WHY not API Gateway in front of the backend:
# API Gateway adds request schema validation, throttling, API keys,
# SDK generation. For an internal service consumed only by your own
# frontend, that is unnecessary complexity + $3.50/million requests.

module "alb" {
  source = "terraform-aws-modules/alb/aws"
  # Pinned to the v10 line on purpose. The listener-rule syntax below
  # (actions = [{ forward = { ... } }]) only exists from v10; the v9 modules
  # expect actions = [{ type = "forward", ... }] and fail at PLAN time with
  # "Insufficient action blocks". `terraform validate` does NOT catch this.
  version = "10.5.1"

  name   = "${local.name}-alb"
  vpc_id = module.vpc.vpc_id
  # ALB lives in public subnets — it is the public-facing entry point.
  subnets = module.vpc.public_subnets

  create_security_group = false
  security_groups       = [module.alb_sg.id]

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"

      # DEFAULT action: if no rule matches, send to frontend.
      # This handles all browser requests for the React app (/, /about, etc.)
      forward = {
        target_group_key = "frontend"
      }

      rules = {
        api = {
          # Priority 10 = evaluated FIRST (lower number = higher priority).
          # OVERRIDE: if the path starts with /api/, send to backend instead.
          # This is the entire "one ALB serves both services" mechanism.
          # The browser calls /api/transaction, ALB matches this rule,
          # forwards to the Node.js backend on port 4000.
          # The browser calls /, no rule matches, falls through to frontend.
          priority = 10
          actions = [{
            forward = {
              target_group_key = "backend"
            }
          }]
          conditions = [{
            path_pattern = {
              values = ["/api/*"]
            }
          }]
        }
      }
    }
  }

  target_groups = {
    frontend = {
      create_attachment = false
      backend_protocol  = "HTTP"
      backend_port      = 80   # Nginx serves on port 80
      target_type       = "ip" # Required for Fargate (awsvpc networking)
      health_check = {
        enabled = true
        path    = "/" # ALB pings / to confirm frontend is alive
      }
    }
    backend = {
      create_attachment = false
      backend_protocol  = "HTTP"
      backend_port      = 4000 # Express listens on 4000
      target_type       = "ip"
      health_check = {
        enabled = true
        # WHY /health endpoint: a dedicated health check route returns 200
        # only when the application is genuinely ready to serve traffic.
        # The ALB sends a GET /health every 30 seconds. A container must
        # pass N consecutive checks before traffic is routed to it, and
        # must fail N consecutive checks before it is removed.
        # This is what enables zero-downtime rolling deploys.
        path = "/health"
      }
    }
  }
}

# 4. RDS PostgreSQL

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 7.0"

  identifier = "${local.name}-db"

  engine               = "postgres"
  engine_version       = var.db_engine_version
  family               = "postgres${var.db_engine_version}"
  major_engine_version = var.db_engine_version

  allocated_storage = 20

  db_name        = var.db_name
  username       = var.db_username
  instance_class = var.db_instance_class

  # WHY manage_master_user_password = true:
  # This single boolean is one of the most important security decisions.
  # Instead of us setting a password (which would then exist in Terraform
  # variables, potentially in the state file, or in git history), AWS
  # generates the password, stores it in Secrets Manager, and manages
  # rotation natively.
  # The password NEVER appears in our code, our state file, or our CI logs.
  # The alternative — using random_password + manual Secrets Manager secret —
  # is more code, more places to make a mistake, reimplementing something
  # AWS already offers as a single boolean.
  #
  # CROSS-QUESTION: "How does the app get the password if you never set it?"
  # See the ECS backend service below: task_exec_secret_arns and secrets block.
  manage_master_user_password = true
  port                        = 5432

  # RDS goes into the isolated database subnet (no internet route).
  db_subnet_group_name = module.vpc.database_subnet_group_name
  # Only traffic from the backend ECS security group reaches RDS (SG-to-SG chain).
  vpc_security_group_ids = [module.rds_sg.id]
  skip_final_snapshot    = true
}

# 5. ECS Cluster & Fargate Services

# WHY ECS Fargate instead of ECS on EC2:
# EC2-based ECS requires managing cluster nodes: choosing instance types,
# patching the OS, planning capacity, handling spot interruptions.
# Fargate is serverless compute — you define CPU/memory per container,
# AWS handles everything underneath. No nodes to patch or manage.
#
# WHY ECS instead of EKS (Kubernetes):
# EKS gives Kubernetes primitives (deployments, ingress controllers,
# HPA, CRDs) at real operational cost — cluster upgrades, node group
# management, steeper learning curve. For a two-service application on
# a single cloud provider, that complexity is not earned.
#
# CROSS-QUESTION: "When would you pick EKS?"
# When you need Kubernetes-native ecosystem tools (Argo CD, Istio),
# or when you need portability across clouds/hybrid environments.

module "ecs" {
  source       = "terraform-aws-modules/ecs/aws"
  version      = "~> 7.0"
  cluster_name = "${local.name}-cluster"

  # Fargate only — no EC2 capacity providers registered.
  cluster_capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy = {
    FARGATE = { weight = 100 }
  }

  services = {
    # FRONTEND SERVICE (React app served by Nginx)
    frontend = {
      cpu    = var.ecs_frontend_cpu    # default 256 = 0.25 vCPU
      memory = var.ecs_frontend_memory # default 512 MB RAM

      create_security_group = false
      security_group_ids    = [module.ecs_frontend_sg.id]
      # Frontend ECS tasks run in PRIVATE subnets, not public.
      # They are not directly internet-accessible — the ALB fronts them.
      subnet_ids = module.vpc.private_subnets

      container_definitions = {
        frontend = {
          essential = true

          # WHY readonlyRootFilesystem = false (honest trade-off):
          # The ECS module defaults this to TRUE as a security hardening
          # measure — it prevents malware from writing to the container filesystem.
          # We discovered this during live debugging: Nginx crashed immediately
          # with "mkdir /var/cache/nginx failed (30: Read-only file system)".
          # Nginx needs to write its cache and PID file on startup.
          # Proper fix: mount a writable tmpfs volume ONLY for /var/cache/nginx
          # and /var/run (so the rest of the filesystem stays read-only).
          # Fargate supports tmpfs via linuxParameters since January 2026.
          # NOT implemented yet (needs a test deploy). Current state: the entire
          # filesystem is writable. Known trade-off.
          readonlyRootFilesystem = false

          # The ECS module creates this container's CloudWatch log group itself
          # (/aws/ecs/frontend/frontend). Its default retention is 14 days; we
          # set 30 so incident investigations have a longer window.
          cloudwatch_log_group_retention_in_days = 30

          # This is a placeholder image. The CI/CD pipeline overwrites this
          # with the real image URI tagged with the git commit SHA.
          image = "nginx:alpine"

          portMappings = [
            {
              name          = "frontend"
              containerPort = 80
              hostPort      = 80
              protocol      = "tcp"
            }
          ]
        }
      }
      # Wire this ECS service to the ALB frontend target group.
      load_balancer = {
        service = {
          target_group_arn = module.alb.target_groups["frontend"].arn
          container_name   = "frontend"
          container_port   = 80
        }
      }
    }

    # BACKEND SERVICE (Node.js Express API)
    backend = {
      cpu    = var.ecs_backend_cpu    # default 256
      memory = var.ecs_backend_memory # default 512 MB RAM

      create_security_group = false
      security_group_ids    = [module.ecs_backend_sg.id]
      subnet_ids            = module.vpc.private_subnets

      # WHY task_exec_secret_arns:
      # This grants the ECS Task EXECUTION ROLE (not the task role) permission
      # to call secretsmanager:GetSecretValue on this specific ARN.
      # Without this, ECS cannot pull the DB password before starting the container
      # and fails with AccessDeniedException. This was the real fix for the
      # incident: the permission had simply not been granted at all.
      # The execution role is what ECS itself uses (to pull images, fetch secrets,
      # write logs) BEFORE your container code runs.
      # The task role is what your app code uses at RUNTIME.
      #
      # WHY the trailing * on the ARN (honest version):
      # Secrets Manager appends a random 6-character suffix to every secret ARN
      # (e.g. "...:secret:rds!db-xxxx-eq2ug9"). The RDS module output is the
      # secret's real ARN, which ALREADY includes that suffix, so an exact match
      # should work and the * is most likely unnecessary. It was added while
      # debugging the AccessDenied above and has been kept as a defensive,
      # low-risk safety net (it only matches this one secret's ARN prefix).
      # I have not re-tested without it; to prove it, remove the * on the next
      # apply and check that the backend task still starts.
      #
      # CROSS-QUESTION: "Is the wildcard a security risk?"
      # Not meaningfully — the prefix is this one secret's full ARN, so it can
      # only match this secret (plus any ARN that merely extends it).
      task_exec_secret_arns = ["${module.db.db_instance_master_user_secret_arn}*"]

      container_definitions = {
        backend = {
          essential              = true
          readonlyRootFilesystem = false
          image                  = "node:18-alpine" # Placeholder — CI/CD replaces this

          # Module-created log group (/aws/ecs/backend/backend); default is 14
          # days, set to 30 to match the frontend. The dashboard reads from it.
          cloudwatch_log_group_retention_in_days = 30

          portMappings = [
            {
              name          = "backend"
              containerPort = 4000
              hostPort      = 4000
              protocol      = "tcp"
            }
          ]

          # Non-sensitive config is injected as plain environment variables.
          # These are visible in the ECS task definition in the AWS console.
          # DB_HOST comes directly from the Terraform RDS module output —
          # we never need to manually look up or paste the RDS endpoint.
          environment = [
            { name = "DB_HOST", value = module.db.db_instance_address },
            { name = "DB_USER", value = var.db_username },
            { name = "DB_NAME", value = var.db_name },
            { name = "DB_PORT", value = "5432" }
          ]

          # WHY secrets block instead of environment for DB_PASSWORD:
          # The secrets block tells ECS to fetch the value from Secrets Manager
          # and inject it into the container as an env var AT STARTUP.
          # The password never appears in the task definition JSON, never in
          # CloudWatch logs, never on disk. It goes directly into process memory.
          # The ":password::" suffix tells ECS to extract the "password" key
          # from the JSON secret (AWS stores it as {"password":"...", "username":"..."}).
          secrets = [
            {
              name      = "DB_PASSWORD"
              valueFrom = "${module.db.db_instance_master_user_secret_arn}:password::"
            }
          ]
        }
      }

      load_balancer = {
        service = {
          target_group_arn = module.alb.target_groups["backend"].arn
          container_name   = "backend"
          container_port   = 4000
        }
      }
    }
  }
}

# 6. ECR Repositories (Docker Image Registry)

resource "aws_ecr_repository" "frontend" {
  name = "${local.name}-frontend"
  # MUTABLE tags: the same tag (e.g., "latest") can be overwritten.
  # The CI/CD pipeline uses git SHA tags which are inherently unique,
  # so mutability vs immutability of tags is moot here.
  # An IMMUTABLE setting would prevent any tag from being overwritten —
  # stricter, but requires strict tag discipline in the pipeline.
  image_tag_mutability = "MUTABLE"
  # force_delete = true: allows Terraform to delete the repo even if it
  # contains images. Default is false — deletion would fail if images exist.
  # Set to true here to make "terraform destroy" cleaner in dev/demo contexts.
  force_delete = true
}

resource "aws_ecr_repository" "backend" {
  name                 = "${local.name}-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# GitHub Actions OIDC — Keyless CI/CD Authentication

# WHY OIDC instead of long-lived AWS access keys stored as GitHub secrets:
# Long-lived IAM access keys stored as GitHub repo secrets are a standing
# security liability. If the repo is compromised, the attacker gets permanent
# AWS credentials valid until someone notices and manually rotates them.
#
# OIDC (OpenID Connect) works differently:
#   1. GitHub issues a short-lived signed JWT (JSON Web Token) for each run.
#   2. The pipeline sends this JWT to AWS STS.
#   3. AWS verifies the JWT signature against GitHub's public OIDC metadata.
#   4. AWS returns temporary credentials valid only for that pipeline run.
# Once the run ends, the credentials expire. A leaked token from a finished
# run is completely useless.
#
# CROSS-QUESTION: "What is stored as a GitHub secret if not AWS keys?"
# The only AWS-related secret is AWS_ACCOUNT_ID — a 12-digit number, not a
# credential. It is needed to construct the IAM role ARN the pipeline assumes.
# (The workflow's only other secret is SLACK_WEBHOOK_URL, for failure alerts —
# it grants no AWS access.)

# Fetch GitHub's TLS certificate to extract its thumbprint.
# AWS requires this thumbprint to verify GitHub's OIDC identity provider.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Register GitHub as a trusted OIDC identity provider in this AWS account.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # thumbprint_list: the TLS cert fingerprint of GitHub's OIDC server.
  # AWS uses this to verify that tokens are genuinely from GitHub.
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # WHY the sub claim condition matters:
    # Without it, ANY GitHub repository could exchange a token for AWS credentials.
    # The sub claim embeds exactly which repo/workflow/environment issued the token.
    # The condition below scopes trust to this specific repository only.
    #
    # WHY numeric IDs instead of repo name (e.g., not "repo:username/reponame"):
    # GitHub migrated to immutable numeric IDs in the sub claim to prevent
    # trust-policy hijacking: if a repo is deleted and recreated with the same
    # name, the numeric ID changes, so the old trust policy stops matching.
    # This was a real debugging incident — the initial pipeline setup used the
    # name-based format, which failed. I decoded the actual JWT from a failed
    # run (using jwt.io) to see the real sub claim, then updated this condition.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:bindukumarbr@121097989/octa-byte-app@1351143352:*"]
    }
    condition {
      # aud = audience. Must equal sts.amazonaws.com to confirm the token
      # is intended for AWS STS and not some other service.
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
}

# WHY least-privilege permissions (not AdministratorAccess):
# The role only gets exactly the permissions the pipeline needs:
# - ECR: login + push images
# - ECS: update service + read/write task definitions
# - IAM: PassRole only for the specific ECS task execution roles
# It cannot create IAM users, delete S3 buckets, access Secrets Manager,
# or do anything outside its deployment scope.
data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    sid     = "ECRLogin"
    effect  = "Allow"
    actions = ["ecr:GetAuthorizationToken"]
    # GetAuthorizationToken cannot be scoped to a specific repo —
    # it is an account-level action that returns a login token.
    resources = ["*"]
  }

  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload"
    ]
    # Scoped ONLY to the two ECR repos this pipeline manages.
    resources = [
      aws_ecr_repository.frontend.arn,
      aws_ecr_repository.backend.arn
    ]
  }

  statement {
    sid    = "ECSDeploy"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices"
    ]
    # Scoped to the specific ECS services — not all services in the account.
    resources = [
      "arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:service/${module.ecs.cluster_name}/frontend",
      "arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:service/${module.ecs.cluster_name}/backend"
    ]
  }

  statement {
    sid    = "ECSTaskDef"
    effect = "Allow"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition"
    ]
    # Task definition ARNs include a version number that changes on every
    # deploy, making it impractical to pre-scope them. "*" is accepted here.
    resources = ["*"]
  }

  statement {
    sid     = "IAMPassRole"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    # WHY iam:PassRole is needed:
    # When the pipeline registers a new ECS task definition, it specifies
    # which IAM roles the task should use (execution role + task role).
    # AWS requires the caller to have PassRole on those specific roles
    # to prevent privilege escalation (attaching a more powerful role to a task).
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/frontend-tasks-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/frontend-task-exec-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/backend-tasks-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/backend-task-exec-*"
    ]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "github-actions-deploy-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}
