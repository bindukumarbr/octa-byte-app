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
  value       = module.alb.dns_name
}

# ECR Outputs

output "ecr_frontend_repository_url" {
  description = "The URL of the frontend ECR repository (used in CI/CD)"
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecr_backend_repository_url" {
  description = "The URL of the backend ECR repository (used in CI/CD)"
  value       = aws_ecr_repository.backend.repository_url
}


# Database Outputs
output "db_endpoint" {
  description = "The connection endpoint for the RDS database"
  value       = module.db.db_instance_address
  sensitive   = true
}

output "db_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the DB password"
  value       = module.db.db_instance_master_user_secret_arn
  sensitive   = true
}

# ECS Outputs
output "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  value       = module.ecs.cluster_name
}
