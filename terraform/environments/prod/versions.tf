# INTERVIEW NOTE: This file pins the exact versions of Terraform
# and all providers. Without version pinning, running "terraform init"
# a month later could silently pull a newer provider version with
# breaking changes, causing your existing code to fail or behave
# differently with no code changes on your part.

terraform {
  # WHY >= 1.11.0 specifically:
  # use_lockfile = true in backend.tf requires Terraform 1.10+.
  # We pin to 1.11.0 (slightly above the minimum) to ensure we are
  # on a stable release that fully supports native S3 locking.
  # This is what allowed us to remove the DynamoDB table.
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"

      # ~> 6.0 means: allow any 6.x release but NOT 7.0.
      # This is called the "pessimistic constraint operator".
      # It prevents a major version bump from silently breaking your
      # resource definitions. A major version (6 -> 7) often includes
      # breaking changes in argument names or resource behaviour.
      #
      # CROSS-QUESTION: "What does ~> mean?"
      # It is equivalent to: >= 6.0, < 7.0
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.13.0"
    }
  }
}

# WHY var.aws_region instead of hardcoding "us-east-1":
# Keeping the region as a variable means the same Terraform code
# could deploy to a different region by changing one .tfvars line.
# It also makes the region explicit and visible in variables.tf
# rather than buried in a provider block.
provider "aws" {
  region = var.aws_region
}
