
resource "aws_prometheus_workspace" "hyperpod" {
  count = var.create_prometheus_workspace ? 1 : 0

  alias = "${var.resource_name_prefix}-ampws"

  tags = {
    SageMaker = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}
