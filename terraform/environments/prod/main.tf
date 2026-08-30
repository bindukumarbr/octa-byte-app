data "aws_availability_zones" "available" { state = "available" }

locals {
  name     = "${var.project_name}-${var.environment}"
  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)
}

// 1. VPC

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.2"

  name = "${local.name}-vpc"
  cidr = local.vpc_cidr
  azs  = local.azs

  public_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 2)]
  database_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 4)]

  enable_nat_gateway           = true
  single_nat_gateway           = true
  create_database_subnet_group = true
}

# 2. Security Groups

module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0"

  name   = "${local.name}-alb-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = {
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

module "ecs_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name   = "${local.name}-ecs-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = {
    from_alb = {
      from_port                    = 80
      to_port                      = 80
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb_sg.id
      description                  = "Allow traffic from ALB"
    }
    backend_from_alb = {
      from_port                    = 4000
      to_port                      = 4000
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb_sg.id
      description                  = "Allow backend traffic from ALB"
    }
  }

  egress_rules = {
    allow_all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
}

module "rds_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name   = "${local.name}-rds-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = {
    from_ecs = {
      from_port                    = 5432
      to_port                      = 5432
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.ecs_sg.id
      description                  = "Allow PostgreSQL traffic from ECS"
    }
  }
}

# 3. Application Load Balancer (Public)

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "10.5.1"

  name    = "${local.name}-alb"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  create_security_group = false
  security_groups       = [module.alb_sg.id]

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "frontend"
      }
      rules = {
        api = {
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
      backend_port      = 80
      target_type       = "ip"
      health_check = {
        enabled = true
        path    = "/"
      }
    }
    backend = {
      create_attachment = false
      backend_protocol  = "HTTP"
      backend_port      = 4000
      target_type       = "ip"
      health_check = {
        enabled = true
        path    = "/health"
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

  db_name                     = var.db_name
  username                    = var.db_username
  instance_class              = var.db_instance_class
  manage_master_user_password = true
  port                        = 5432

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [module.rds_sg.id]
  skip_final_snapshot    = true
}

# 5. ECS Cluster & Fargate

module "ecs" {
  source                     = "terraform-aws-modules/ecs/aws"
  version                    = "~> 7.0"
  cluster_name               = "${local.name}-cluster"
  cluster_capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy = {
    FARGATE = {
      weight = 100
    }
  }
  services = {
    frontend = {
      cpu    = 256
      memory = 512

      create_security_group = false
      security_group_ids    = [module.ecs_sg.id]
      subnet_ids            = module.vpc.private_subnets

      container_definitions = {
        frontend = {
          essential = true
          image     = "nginx:alpine"
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
      load_balancer = {
        service = {
          target_group_arn = module.alb.target_groups["frontend"].arn
          container_name   = "frontend"
          container_port   = 80
        }
      }
    }

    backend = {
      cpu    = 256
      memory = 512

      create_security_group = false
      security_group_ids    = [module.ecs_sg.id]
      subnet_ids            = module.vpc.private_subnets

      container_definitions = {
        backend = {
          essential = true
          image     = "node:18-alpine" # Placeholder until CI/CD
          portMappings = [
            {
              name          = "backend"
              containerPort = 4000
              hostPort      = 4000
              protocol      = "tcp"
            }
          ]
          environment = [
            { name = "DB_HOST", value = module.db.db_instance_address },
            { name = "DB_USER", value = var.db_username },
            { name = "DB_NAME", value = var.db_name },
            { name = "DB_PORT", value = "5432" }
          ]
          secrets = [
            {
              name      = "DB_PASS"
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

# 6. ECR Repositories

resource "aws_ecr_repository" "frontend" {
  name                 = "${local.name}-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}
resource "aws_ecr_repository" "backend" {
  name                 = "${local.name}-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}











# GitHub Actions OIDC Provider & IAM Role

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["1c58a3a8518e8759bf075b76b750d4f2df264fcd", "6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:bindukumarbr/octa-byte-app:*"] # Allow the specific repository
    }
    condition {
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

data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    sid       = "ECRLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
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
    # Restrict to the specific services created by the module
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "github-actions-deploy-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}
