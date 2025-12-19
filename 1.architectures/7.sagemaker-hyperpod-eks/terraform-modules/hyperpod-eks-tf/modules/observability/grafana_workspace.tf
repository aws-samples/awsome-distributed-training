
# Grafana workspace 
resource "aws_grafana_workspace" "hyperpod" {
  count = local.is_amg_allowed && var.create_grafana_workspace ? 1 : 0

  name                     = local.grafana_workspace_name 
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "CUSTOMER_MANAGED"
  role_arn                 = aws_iam_role.grafana_workspace[0].arn
  
  configuration = jsonencode({
    unifiedAlerting = { enabled = true }
  })

  tags = {
    SageMaker = "true"
  }
}

# Service account and token 
resource "aws_grafana_workspace_service_account" "hyperpod" {
  count = local.is_amg_allowed ? 1 : 0

  name         = "${var.resource_name_prefix}-amgws-sa"
  grafana_role = "ADMIN"
  workspace_id = local.grafana_workspace_id
}

resource "aws_grafana_workspace_service_account_token" "hyperpod" {
  count = local.is_amg_allowed ? 1 : 0

  name               = "${var.resource_name_prefix}-amgws-sa-token"
  service_account_id = aws_grafana_workspace_service_account.hyperpod[0].service_account_id
  seconds_to_live    = 1500
  workspace_id       = local.grafana_workspace_id
}

# Data sources
resource "grafana_data_source" "cloudwatch" {
  count = local.is_amg_allowed ? 1 : 0

  type = "cloudwatch"
  name = "cloudwatch"
  uid  = "cloudwatch"
  
  json_data_encoded = jsonencode({
    authType        = "sigv4"
    sigV4Auth       = true
    sigV4Region     = var.aws_region
    defaultRegion   = var.aws_region
    httpMethod      = "POST"
    sigV4AuthType   = "ec2_iam_role"
  })
}

resource "grafana_data_source" "prometheus" {
  count        = local.is_amg_allowed ? 1 : 0

  type = "prometheus"
  name = "prometheus"
  uid  = "prometheus"
  url  = "https://aps-workspaces.${var.aws_region}.amazonaws.com/workspaces/${local.prometheus_workspace_id}"
  
  json_data_encoded = jsonencode({
    authType        = "sigv4"
    sigV4Auth       = true
    sigV4Region     = var.aws_region
    defaultRegion   = var.aws_region
    httpMethod      = "POST"
    sigV4AuthType   = "ec2_iam_role"
  })
}

resource "grafana_folder" "alerts" {
  count = local.is_amg_allowed ? 1 : 0

  title = "Sagemaker Hyperpod Alerts"
  uid   = "aws-sm-hp-observability-rules"
}

resource "grafana_dashboard" "hyperpod_dashboards" {
  for_each = local.is_amg_allowed ? local.dashboard_uids : {}
  
  config_json = replace(
    local.dashboard_configs[each.key],
    "$${datasource}",
    "prometheus"
  )
}

resource "grafana_rule_group" "hyperpod_alerts" {
  count = local.is_amg_allowed ? 1 : 0

  name             = "sagemaker_hyperpod_alerts"
  folder_uid       = grafana_folder.alerts[0].uid
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
        datasource_uid = grafana_data_source.prometheus[0].uid
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
