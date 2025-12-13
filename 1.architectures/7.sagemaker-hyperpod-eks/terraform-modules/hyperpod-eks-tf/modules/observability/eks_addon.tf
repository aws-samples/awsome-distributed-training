resource "aws_eks_addon" "hyperpod_observability" {
  cluster_name                = var.eks_cluster_name
  addon_name                  = "amazon-sagemaker-hyperpod-observability"
  resolve_conflicts_on_update = "OVERWRITE"
  
  configuration_values = jsonencode({
    ampWorkspace = {
      prometheusEndpoint = "https://aps-workspaces.${var.region}.amazonaws.com/workspaces/${local.prometheus_workspace_id}"
      arn               = local.prometheus_workspace_arn
    }
    metricsProvider = {
      trainingMetrics = {
        level          = var.training_metric_level
        scrapeInterval = 30
      }
      inferenceMetrics = {
        level          = "BASIC"
        scrapeInterval = 30
      }
      taskGovernanceMetrics = {
        level          = var.task_governance_metric_level
        scrapeInterval = 30
      }
      scalingMetrics = {
        level          = var.scaling_metric_level
        scrapeInterval = 30
      }
      customMetrics = {
        level          = var.cluster_metric_level
        scrapeInterval = 30
      }
      nodeMetrics = {
        level          = var.node_metric_level
        scrapeInterval = 30
      }
      acceleratedComputeMetrics = {
        level          = var.accelerated_compute_metric_level
        scrapeInterval = 30
      }
      networkMetrics = {
        level          = var.network_metric_level
        scrapeInterval = 30
      }
    }
    amgWorkspace = var.create_grafana_workspace == "disabled" ? null : {
      workspaceName = local.grafana_workspace_name
      arn          = local.grafana_workspace_arn
    }
    logging = {
      enabled = var.logging_enabled
    }
  })

  pod_identity_association {
    role_arn        = local.observability_role_arn
    service_account = "hyperpod-observability-operator-otel-collector"
  }

  tags = {
    SageMaker = "true"
  }

  depends_on = [
    aws_grafana_workspace.hyperpod,
    aws_prometheus_workspace.hyperpod
  ]
}
