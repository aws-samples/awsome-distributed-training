
resource "aws_prometheus_workspace" "hyperpod" {
  count = var.create_prometheus_workspace ? 1 : 0

  alias = local.prometheus_workspace_name

  tags = {
    SageMaker = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}
