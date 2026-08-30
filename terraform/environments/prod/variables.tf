variable "aws_region" {
  description = "The AWS region to deploy all resources into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "The deployment environment name (e.g. prod, staging)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "The name of the project, used as a prefix for all resources"
  type        = string
  default     = "octa-byte"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_instance_class" {
  description = "The instance class for the RDS database"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "The name of the PostgreSQL database"
  type        = string
  default     = "octadb"
}

variable "db_username" {
  description = "The master username for the PostgreSQL database"
  type        = string
  default     = "dbadmin"
}

variable "ecs_frontend_cpu" {
  description = "CPU units for the frontend ECS task (1024 = 1 vCPU)"
  type        = number
  default     = 256
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
  default     = "15"
}

