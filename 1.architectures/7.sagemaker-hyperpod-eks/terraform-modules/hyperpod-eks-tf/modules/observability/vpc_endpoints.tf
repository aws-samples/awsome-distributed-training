
# Grafana VPC Endpoint
resource "aws_vpc_endpoint" "grafana" {
  count = local.is_amg_allowed ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.grafana-workspace"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = {
    Name      = "${var.resource_name_prefix}-gVpce"
    SageMaker = "true"
  }
}

# Prometheus VPC Endpoint
resource "aws_vpc_endpoint" "prometheus" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.aps-workspaces"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = {
    Name      = "${var.resource_name_prefix}-pVpce"
    SageMaker = "true"
  }
}
