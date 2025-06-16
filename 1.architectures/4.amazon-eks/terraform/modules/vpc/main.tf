module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.name
  cidr = var.cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway = var.enable_nat_gateway
  enable_vpn_gateway = var.enable_vpn_gateway
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  # Single NAT Gateway for cost optimization (can be changed to one_nat_gateway_per_az = true for HA)
  single_nat_gateway = var.single_nat_gateway
  one_nat_gateway_per_az = var.one_nat_gateway_per_az

  # VPC Flow Logs
  enable_flow_log                      = var.enable_flow_log
  create_flow_log_cloudwatch_iam_role  = var.create_flow_log_cloudwatch_iam_role
  create_flow_log_cloudwatch_log_group = var.create_flow_log_cloudwatch_log_group

  # Public subnet tags for ELB
  public_subnet_tags = merge(var.public_subnet_tags, {
    "kubernetes.io/role/elb" = "1"
  })

  # Private subnet tags for internal ELB
  private_subnet_tags = merge(var.private_subnet_tags, {
    "kubernetes.io/role/internal-elb" = "1"
  })

  tags = var.tags
}

# VPC Endpoints for cost optimization and security
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(module.vpc.private_route_table_ids, module.vpc.public_route_table_ids)
  
  tags = merge(var.tags, {
    Name = "${var.name}-s3-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = merge(var.tags, {
    Name = "${var.name}-ecr-dkr-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = merge(var.tags, {
    Name = "${var.name}-ecr-api-endpoint"
  })
}

resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = merge(var.tags, {
    Name = "${var.name}-ec2-endpoint"
  })
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = merge(var.tags, {
    Name = "${var.name}-logs-endpoint"
  })
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = merge(var.tags, {
    Name = "${var.name}-sts-endpoint"
  })
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-vpc-endpoints"
  })
}

data "aws_region" "current" {}