# INTERVIEW NOTE: outputs.tf exposes values from the Terraform run to the
# outside world. After "terraform apply", these print to the terminal and
# are stored in the state file.
#
# WHY outputs matter for a DevOps workflow:
# They bridge the gap between the infrastructure layer (Terraform) and the
# consumer layer (CI/CD pipeline, developers, monitoring tools).
# Without outputs, you would have to log into the AWS console to find the
# ALB DNS name or ECR repository URL after every apply.

# VPC Outputs

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "The IDs of the public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "The IDs of the private subnets"
  value       = module.vpc.private_subnets
}

# Load Balancer Outputs

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer (access your app here)"
  # This is the URL you open in a browser to reach the live application.
  # Terraform prints this automatically at the end of every apply.
  # In a real setup, you would create a Route53 CNAME pointing your
  # domain (e.g., app.example.com) to this ALB DNS name.
  value = module.alb.dns_name
}

# ECR Outputs

output "ecr_frontend_repository_url" {
  description = "The URL of the frontend ECR repository (used in CI/CD)"
  # Informational: handy for a manual `docker push`. The GitHub Actions
  # pipeline does NOT read this output; it builds the same URI from the
  # ECR_FRONTEND_REPO / ECR_BACKEND_REPO values in deploy.yml's env block
  # plus the registry returned by the ECR login step, and appends :<git_sha>.
  # Format: <account_id>.dkr.ecr.<region>.amazonaws.com/<repo_name>
  value = aws_ecr_repository.frontend.repository_url
}

output "ecr_backend_repository_url" {
  description = "The URL of the backend ECR repository (used in CI/CD)"
  value       = aws_ecr_repository.backend.repository_url
}

# Database Outputs

output "db_endpoint" {
  description = "The connection endpoint for the RDS database"
  value       = module.db.db_instance_address
  # WHY sensitive = true:
  # Terraform will NOT print this value to the terminal during apply/output.
  # It also masks it in CI/CD logs. To read it explicitly:
  #   terraform output -raw db_endpoint
  # This prevents the RDS hostname from appearing in pipeline logs
  # where it could be scraped by an attacker to target the endpoint.
  sensitive = true
}

output "db_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the DB password"
  # This ARN is what the ECS backend task definition references
  # in its "secrets" block to inject DB_PASSWORD at container startup.
  # It is also what you would pass to other services or Lambda functions
  # that need database access, so they can fetch the same managed secret.
  value     = module.db.db_instance_master_user_secret_arn
  sensitive = true
}

# ECS Outputs

output "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  # Informational. deploy.yml does NOT read this output: it hardcodes the same
  # name in env.ECS_CLUSTER ("octa-byte-prod-cluster", i.e. project_name +
  # environment + "-cluster"). That means the name lives in two places, so if
  # the naming convention in variables.tf ever changes, update deploy.yml too.
  value = module.ecs.cluster_name
}
