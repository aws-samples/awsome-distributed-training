terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.27.0"
    }
    grafana = {
      source = "grafana/grafana"
      version = ">= 2.0.0"
    }
    http = {
      source = "hashicorp/http"
    }
  }
}
