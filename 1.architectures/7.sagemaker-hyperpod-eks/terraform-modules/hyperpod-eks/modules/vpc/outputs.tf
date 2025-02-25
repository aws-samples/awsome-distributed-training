output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_1_id" {
  description = "The ID of the first public subnet"
  value       = aws_subnet.public_1.id
}

output "public_subnet_2_id" {
  description = "The ID of the second public subnet"
  value       = aws_subnet.public_2.id
}

output "nat_gateway_1_id" {
  description = "The ID of the first NAT Gateway"
  value       = aws_nat_gateway.nat_1.id
}

output "nat_gateway_2_id" {
  description = "The ID of the second NAT Gateway"
  value       = aws_nat_gateway.nat_2.id
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "public_route_table_id" {
  description = "The ID of the public route table"
  value       = aws_route_table.public.id
}

output "nat_gateway_1_eip" {
  description = "The Elastic IP address of the first NAT Gateway"
  value       = aws_eip.nat_1.public_ip
}

output "nat_gateway_2_eip" {
  description = "The Elastic IP address of the second NAT Gateway"
  value       = aws_eip.nat_2.public_ip
}

output "availability_zones" {
  description = "List of availability zones used in the VPC"
  value       = [aws_subnet.public_1.availability_zone, aws_subnet.public_2.availability_zone]
}
