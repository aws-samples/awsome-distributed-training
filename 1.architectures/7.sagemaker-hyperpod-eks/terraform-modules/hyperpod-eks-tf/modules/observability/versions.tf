terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0"
    }
    grafana = {
      source = "grafana/grafana"
      version = "~> 2.0"
    }
    http = {
      source = "hashicorp/http"
    }
  }
}

provider "grafana" {
  url  = aws_grafana_workspace.hyperpod.endpoint
  auth = aws_grafana_workspace_service_account_token.hyperpod.key
}