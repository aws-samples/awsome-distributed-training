output "vpc_endpoint_id" {
  description = "The ID of the VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_state" {
  description = "The state of the VPC endpoint"
  value       = aws_vpc_endpoint.s3.state
}
