data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    {
      Name = "${var.resource_name_prefix}-SMHP-VPC"
    },
    var.tags
  )
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    {
      Name = "${var.resource_name_prefix}-SMHP-IGW"
    },
    var.tags
  )
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(
    {
      Name = "${var.resource_name_prefix}-SMHP-Public1"
    },
    var.tags
  )
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = merge(
    {
      Name = "${var.resource_name_prefix}-SMHP-Public2"
    },
    var.tags
  )
}

resource "aws_eip" "nat_1" {
  domain = "vpc"

  depends_on = [aws_internet_gateway.main]

  tags = merge(
    {
      Name = "${var.resource_name_prefix}-SMHP-NAT1-EIP"
    },
    var.tags
  )
}

resource "aws_eip" "nat_2" {
  domain = "vpc"

  depends_on = [aws_internet_gateway.main]

  tags = merge(
    {
      Name = "${var.resource_name_prefix}-SMHP-NAT2-EIP"
    },
    var.tags
  )
}

resource "aws_nat_gateway" "nat_1" {
  allocation_id = aws_eip.nat_1.id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [aws_internet_gateway.main]

  tags = merge(
    {
      Name = "${var.resource_name_prefix}-SMHP-NAT1"
    },
    var.tags
  )
}

resource "aws_nat_gateway" "nat_2" {
  allocation_id = aws_eip.nat_2.id
  subnet_id     = aws_subnet.public_2.id

  depends_on = [aws_internet_gateway.main]

  tags = merge(
    {
      Name = "${var.resource_name_prefix}-SMHP-NAT2"
    },
    var.tags
  )
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    {
      Name = "${var.resource_name_prefix}-SMHP-Public-Routes"
    },
    var.tags
  )
}

resource "aws_route_table_association" "public_1" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public_1.id
}

resource "aws_route_table_association" "public_2" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public_2.id
}
