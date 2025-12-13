output "grafana_vpc_endpoint_id" {
  description = "Grafana VPC Endpoint ID"
  value       = local.is_amg_allowed ? aws_vpc_endpoint.grafana[0].id : null
}

output "prometheus_vpc_endpoint_id" {
  description = "Prometheus VPC Endpoint ID"
  value       = aws_vpc_endpoint.prometheus.id
}

output "prometheus_workspace_id" {
  description = "Prometheus Workspace ID"
  value       = var.create_prometheus_workspace ? aws_prometheus_workspace.this[0].id : var.prometheus_workspace_id
}

output "prometheus_workspace_arn" {
  description = "Prometheus Workspace ARN"
  value       = var.create_prometheus_workspace ? aws_prometheus_workspace.this[0].arn : var.prometheus_workspace_arn
}

output "prometheus_workspace_endpoint" {
  description = "Prometheus Workspace Endpoint"
  value       = var.create_prometheus_workspace ? aws_prometheus_workspace.this[0].prometheus_endpoint : var.prometheus_workspace_endpoint
}

output "observability_role_arn" {
  description = "HyperPod Observability IAM Role ARN"
  value       = var.create_hyperpod_observability_role ? aws_iam_role.hyperpod_observability_addon[0].arn : var.hyperpod_observability_role_arn
}

output "grafana_workspace_role_arn" {
  description = "HyperPod Observability Grafana IAM Role ARN"
  value       = var.create_grafana_role && local.is_amg_allowed ? aws_iam_role.grafana_workspace[0].arn : var.grafana_role
}

output "grafana_workspace_id" {
  value = aws_grafana_workspace.hyperpod.id
}

output "grafana_workspace_arn" {
  value = aws_grafana_workspace.hyperpod.arn
}

output "grafana_workspace_endpoint" {
  value = aws_grafana_workspace.hyperpod.endpoint
}