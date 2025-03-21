resource "aws_vpc_ipv4_cidr_block_association" "additional_cidr" {
  vpc_id     = var.vpc_id
  cidr_block = var.private_subnet_cidr
}

resource "aws_subnet" "private" {
  vpc_id               = var.vpc_id
  cidr_block          = var.private_subnet_cidr
  availability_zone_id = var.availability_zone_id

  # Ensure the subnet is created after the CIDR block is associated
  depends_on = [aws_vpc_ipv4_cidr_block_association.additional_cidr]

  tags = merge(
    {
      Name = "${var.resource_name_prefix}-SMHP-Private1"
    },
    var.tags
  )
}

resource "aws_route_table" "private" {
  vpc_id = var.vpc_id

  tags = merge(
    {
      Name = "${var.resource_name_prefix}-SMHP-Private-Routes"
    },
    var.tags
  )
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route" "nat_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.nat_gateway_id
}
