
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  github_base_url = "https://raw.githubusercontent.com/aws/sagemaker-hyperpod-cluster-setup/refs/heads/main/eks/cloudformation/resources/grafana-lambda-function/lambda_function"
}

# Fetch alert rules from GitHub
data "http" "alert_rules" {
  url = "${local.github_base_url}/rules/templates/alert-rules.yaml"
}

# Fetch dashboard templates from GitHub
data "http" "cluster_dashboard" {
  url = "${local.github_base_url}/dashboards/templates/cluster.json"
}

data "http" "efa_dashboard" {
  url = "${local.github_base_url}/dashboards/templates/efa.json"
}

data "http" "training_dashboard" {
  url = "${local.github_base_url}/dashboards/templates/training.json"
}

data "http" "inference_dashboard" {
  url = "${local.github_base_url}/dashboards/templates/inference.json"
}

data "http" "tasks_dashboard" {
  url = "${local.github_base_url}/dashboards/templates/tasks.json"
}

locals {
  amg_allowed_regions = [
    "us-east-1", "us-east-2", "us-west-2",
    "ap-northeast-1", "ap-northeast-2", "ap-southeast-1", "ap-southeast-2",
    "ca-central-1", "eu-central-1", "eu-west-1", "eu-west-2"
  ]
  
  is_amg_allowed = contains(local.amg_allowed_regions, data.aws_region.current.name) && var.create_grafana_workspace != "disabled"

  dashboard_uids = {
    cluster   = "aws-sm-hp-observability-cluster-v1_0"
    efa       = "aws-sm-hp-observability-efa-v1_0"
    training  = "aws-sm-hp-observability-training-v1_0"
    inference = "aws-sm-hp-observability-inference-v1_0"
    tasks     = "aws-sm-hp-observability-task-v1_0"
  }

  dashboard_configs = {
    cluster   = data.http.cluster_dashboard.response_body
    efa       = data.http.efa_dashboard.response_body
    training  = data.http.training_dashboard.response_body
    inference = data.http.inference_dashboard.response_body
    tasks     = data.http.tasks_dashboard.response_body
  }

  alert_rules = yamldecode(data.http.alert_rules.response_body).groups[0].rules

  # Prometheus workspace values
  prometheus_workspace_id  = var.create_prometheus_workspace ? aws_prometheus_workspace.hyperpod[0].workspace_id : var.prometheus_workspace_id
  prometheus_workspace_arn = var.create_prometheus_workspace ? aws_prometheus_workspace.hyperpod[0].arn : var.prometheus_workspace_arn

  # Grafana workspace values
  grafana_workspace_name = var.create_grafana_workspace == "true" ? aws_grafana_workspace.hyperpod[0].name : var.grafana_workspace_name
  grafana_workspace_arn  = var.create_grafana_workspace == "true" ? aws_grafana_workspace.hyperpod[0].arn : var.grafana_workspace_arn

  # Observability role
  observability_role_arn = var.create_hyperpod_observability_role ? aws_iam_role.hyperpod_observability[0].arn : var.hyperpod_observability_role_arn

  
}
