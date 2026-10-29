# INTERVIEW NOTE: variables.tf declares every input the module accepts.
# WHY separate variables from main.tf:
# Keeping declarations here and values in terraform.tfvars (or passed via -var)
# means the same infrastructure code deploys to different environments
# by simply swapping the values — no touching the resource logic.
# A staging environment would use a smaller db_instance_class and a
# different environment name, nothing else changes.

variable "aws_region" {
  description = "The AWS region to deploy all resources into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "The deployment environment name (e.g. prod, staging)"
  type        = string
  # WHY this variable exists: it feeds into the local.name = "${project_name}-${environment}"
  # pattern in main.tf, which prefixes every resource name.
  # This means all resources are instantly recognisable in the AWS console:
  # "octa-byte-prod-alb", "octa-byte-prod-cluster", etc.
  default = "prod"
}

variable "project_name" {
  description = "The name of the project, used as a prefix for all resources"
  type        = string
  default     = "octa-byte"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  # 10.0.0.0/16 gives 65,536 IP addresses across all subnets.
  # The VPC module carves this into /24 subnets (256 IPs each) for each
  # subnet tier per AZ. For this workload, /16 is far larger than needed
  # but is the standard default that avoids future expansion constraints.
  default = "10.0.0.0/16"
}

variable "db_instance_class" {
  description = "The instance class for the RDS database"
  type        = string
  # db.t3.micro: 2 vCPU, 1 GB RAM. Eligible for AWS Free Tier.
  # For production workloads with real traffic, db.t3.small or db.t3.medium
  # would be the minimum. This is sufficient for a demo/assignment workload.
  # CROSS-QUESTION: "How would you right-size the RDS instance?"
  # Observe actual query load and connection counts over time (the CloudWatch
  # RDS metrics here, or RDS Performance Insights, which is NOT enabled in
  # this project), then choose the smallest instance class where CPU stays
  # below 50% and connections stay well below the instance limit.
  default = "db.t3.micro"
}

variable "db_name" {
  description = "The name of the PostgreSQL database"
  type        = string
  default     = "octadb"
}

variable "db_username" {
  description = "The master username for the PostgreSQL database"
  type        = string
  # WHY db_username is a variable but db_password is NOT:
  # The username is not sensitive — it appears in connection strings,
  # CloudWatch logs, and app config. It does not need to be secret.
  # The password is managed entirely by AWS Secrets Manager (see main.tf
  # manage_master_user_password = true). It never appears in variables
  # or the state file. This is the deliberate split: username = config,
  # password = secret.
  default = "dbadmin"
}

variable "ecs_frontend_cpu" {
  description = "CPU units for the frontend ECS task (1024 = 1 vCPU)"
  type        = number
  # 256 CPU units = 0.25 vCPU. ECS Fargate CPU unit denominations:
  # 256, 512, 1024, 2048, 4096. Memory must fall within allowed ranges
  # for each CPU value (256 CPU allows 512–2048 MB).
  default = 256
}

variable "ecs_frontend_memory" {
  description = "Memory (MB) for the frontend ECS task"
  type        = number
  default     = 512
}

variable "ecs_backend_cpu" {
  description = "CPU units for the backend ECS task"
  type        = number
  default     = 256
}

variable "ecs_backend_memory" {
  description = "Memory (MB) for the backend ECS task"
  type        = number
  default     = 512
}

variable "db_engine_version" {
  description = "The PostgreSQL engine version. Changing this automatically updates family and major_engine_version."
  type        = string
  # Pinned to PostgreSQL 15. Changing this triggers an RDS engine upgrade.
  # The "family" argument in main.tf is derived from this value:
  # family = "postgres${var.db_engine_version}" -> "postgres15"
  # This ensures the parameter group family stays aligned with the engine.
  default = "15"
}
