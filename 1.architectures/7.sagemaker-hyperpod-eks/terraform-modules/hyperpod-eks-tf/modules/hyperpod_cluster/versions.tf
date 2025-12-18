terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.27.0"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.64.0"
    }
  }
}
