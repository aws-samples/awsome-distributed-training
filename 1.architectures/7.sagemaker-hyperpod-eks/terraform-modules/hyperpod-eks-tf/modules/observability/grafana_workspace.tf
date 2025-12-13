
# Grafana workspace 
resource "aws_grafana_workspace" "hyperpod" {
  name                     = var.grafana_workspace_name
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type         = "CUSTOMER_MANAGED"
  role_arn               = var.grafana_workspace_role_arn
  
  configuration = jsonencode({
    unifiedAlerting = { enabled = true }
  })

  tags = {
    SageMaker = "true"
  }
}

# Service account and token 
resource "aws_grafana_workspace_service_account" "hyperpod" {
  name         = var.grafana_service_account_name
  grafana_role = "ADMIN"
  workspace_id = aws_grafana_workspace.hyperpod.id
}

resource "aws_grafana_workspace_service_account_token" "hyperpod" {
  name               = "${var.grafana_service_account_name}-token"
  service_account_id = aws_grafana_workspace_service_account.hyperpod.id
  seconds_to_live    = 1500
  workspace_id       = aws_grafana_workspace.hyperpod.id
}

# Data sources
resource "grafana_data_source" "cloudwatch" {
  type = "cloudwatch"
  name = "cloudwatch"
  uid  = "cloudwatch"
  
  json_data_encoded = jsonencode({
    authType        = "sigv4"
    sigV4Auth       = true
    sigV4Region     = data.aws_region.current.id
    defaultRegion   = data.aws_region.current.id
    httpMethod      = "POST"
    sigV4AuthType   = "ec2_iam_role"
  })
}

resource "grafana_data_source" "prometheus" {
  type = "prometheus"
  name = "prometheus"
  uid  = "prometheus"
  url  = "https://aps-workspaces.${var.region}.amazonaws.com/workspaces/${var.prometheus_workspace_id}/api"
  
  json_data_encoded = jsonencode({
    authType        = "sigv4"
    sigV4Auth       = true
    sigV4Region     = data.aws_region.current.id
    defaultRegion   = data.aws_region.current.id
    httpMethod      = "POST"
    sigV4AuthType   = "ec2_iam_role"
  })
}

resource "grafana_folder" "alerts" {
  title = "Sagemaker Hyperpod Alerts"
  uid   = "aws-sm-hp-observability-rules"
}

resource "grafana_dashboard" "hyperpod_dashboards" {
  for_each = local.dashboard_uids
  
  config_json = replace(
    local.dashboard_configs[each.key],
    "$${datasource}",
    "prometheus"
  )
}

resource "grafana_rule_group" "hyperpod_alerts" {
  name             = "sagemaker_hyperpod_alerts"
  folder_uid       = grafana_folder.alerts.uid
  interval_seconds = 300
  
  dynamic "rule" {
    for_each = local.alert_rules
    content {
      name           = rule.value.alert
      condition      = "A"
      no_data_state  = "OK"
      exec_err_state = "Error"
      for            = rule.value.for != null ? rule.value.for : "0m"
      
      annotations = rule.value.annotations
      labels      = rule.value.labels
      
      data {
        ref_id = "A"
        query_type = ""
        relative_time_range {
          from = 600
          to   = 0
        }
        datasource_uid = grafana_data_source.prometheus.uid
        model = jsonencode({
          refId        = "A"
          expr         = rule.value.expr
          range        = false
          instant      = true
          editorMode   = "code"
          legendFormat = "__auto"
        })
      }
    }
  }
}
