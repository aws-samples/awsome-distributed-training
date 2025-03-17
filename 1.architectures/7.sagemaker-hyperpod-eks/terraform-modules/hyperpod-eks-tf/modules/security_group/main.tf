locals {
  security_group_id = var.create_new_sg ? aws_security_group.no_ingress[0].id : var.existing_security_group_id
}

resource "aws_security_group" "no_ingress" {
  count = var.create_new_sg ? 1 : 0

  name        = "${var.resource_name_prefix}-no-ingress-sg"
  description = "Security group with no ingress rule"
  vpc_id      = var.vpc_id

  tags = merge(
    {
      Name = "${var.resource_name_prefix}-no-ingress-sg"
    },
    var.tags
  )
}

resource "aws_security_group_rule" "intra_sg_ingress" {
  description              = "Allow traffic within the security group"
  type                    = "ingress"
  from_port               = -1
  to_port                 = -1
  protocol                = -1
  security_group_id       = local.security_group_id
  source_security_group_id = local.security_group_id
}

resource "aws_security_group_rule" "intra_sg_egress" {
  description              = "Allow traffic within the security group"
  type                    = "egress"
  from_port               = -1
  to_port                 = -1
  protocol                = -1
  security_group_id       = local.security_group_id
  source_security_group_id = local.security_group_id
}

resource "aws_security_group_rule" "internet_egress" {
  description = "Allow traffic to internet"
  type        = "egress"
  from_port   = -1
  to_port     = -1
  protocol    = -1
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = local.security_group_id
}

resource "aws_security_group_rule" "fsx_lustre_ingress_988" {
  description              = "Allows Lustre traffic between FSx for Lustre file servers and Lustre clients"
  type                    = "ingress"
  from_port               = 988
  to_port                 = 988
  protocol                = "tcp"
  security_group_id       = local.security_group_id
  source_security_group_id = local.security_group_id
}

resource "aws_security_group_rule" "fsx_lustre_ingress_1018_1023" {
  description              = "Allows Lustre traffic between FSx for Lustre file servers and Lustre clients"
  type                    = "ingress"
  from_port               = 1018
  to_port                 = 1023
  protocol                = "tcp"
  security_group_id       = local.security_group_id
  source_security_group_id = local.security_group_id
}
