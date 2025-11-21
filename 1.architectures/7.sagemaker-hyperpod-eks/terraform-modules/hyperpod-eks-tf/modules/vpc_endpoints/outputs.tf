output "s3_vpc_endpoint_id" {
  description = "The ID of the S3 VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "s3_vpc_endpoint_state" {
  description = "The state of the S3 VPC endpoint"
  value       = aws_vpc_endpoint.s3.state
}

output "lambda_vpc_endpoint_id" {
  description = "The ID of the Lambda VPC endpoint"
  value       = length(aws_vpc_endpoint.lambda) > 0 ? aws_vpc_endpoint.lambda[0].id : null
}

output "lambda_vpc_endpoint_state" {
  description = "The state of the Lambda VPC endpoint"
  value       = length(aws_vpc_endpoint.lambda) > 0 ? aws_vpc_endpoint.lambda[0].state : null
}

output "sqs_vpc_endpoint_id" {
  description = "The ID of the SQS VPC endpoint"
  value       = length(aws_vpc_endpoint.sqs) > 0 ? aws_vpc_endpoint.sqs[0].id : null
}

output "sqs_vpc_endpoint_state" {
  description = "The state of the SQS VPC endpoint"
  value       = length(aws_vpc_endpoint.sqs) > 0 ? aws_vpc_endpoint.sqs[0].state : null
}
