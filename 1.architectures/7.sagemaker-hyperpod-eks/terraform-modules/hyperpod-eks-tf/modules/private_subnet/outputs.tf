output "private_subnet_id" {
  description = "The ID of the private subnet"
  value       = aws_subnet.private.id
}

output "private_subnet_cidr" {
  description = "The CIDR block of the private subnet"
  value       = aws_subnet.private.cidr_block
}

output "private_subnet_availability_zone_id" {
  description = "The Availability Zone ID of the private subnet"
  value       = aws_subnet.private.availability_zone_id
}

output "private_route_table_id" {
  description = "The ID of the private route table"
  value       = aws_route_table.private.id
}

output "additional_cidr_association_id" {
  description = "The ID of the additional CIDR block association"
  value       = aws_vpc_ipv4_cidr_block_association.additional_cidr.id
}
