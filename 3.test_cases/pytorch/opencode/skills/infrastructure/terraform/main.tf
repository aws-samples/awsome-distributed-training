terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

module "fsdp_codebuild" {
  source = "./modules/fsdp-builder"

  project_name     = var.project_name
  repository_name  = var.repository_name
  github_repository = var.github_repository
  github_branch    = var.github_branch
  region           = var.region
  build_timeout    = var.build_timeout
  compute_type     = var.compute_type
  enable_webhook   = var.enable_webhook
  enable_scheduled_builds = var.enable_scheduled_builds
  schedule_expression = var.schedule_expression

  tags = {
    Project     = "pytorch-fsdp"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
