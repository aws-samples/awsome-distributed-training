output "helm_release_name" {
  description = "Name of the inference operator Helm release"
  value       = helm_release.inference_operator.name
}

output "helm_release_status" {
  description = "Status of the inference operator Helm release"
  value       = helm_release.inference_operator.status
}

output "inference_operator_role_arn" {
  description = "ARN of the inference operator IAM role"
  value       = aws_iam_role.inference_operator.arn
}

output "gated_role_arn" {
  description = "ARN of the gated model access IAM role"
  value       = aws_iam_role.gated.arn
}

output "alb_controller_sa_role_arn" {
  description = "ARN of the ALB controller service account IAM role"
  value       = aws_iam_role.alb_controller_sa.arn
}

output "s3_csi_role_arn" {
  description = "ARN of the S3 CSI driver IAM role"
  value       = aws_iam_role.s3_csi_sa.arn
}

output "keda_role_arn" {
  description = "ARN of the KEDA IAM role"
  value       = aws_iam_role.keda.arn
}

output "tls_certificates_bucket_name" {
  description = "Name of the TLS certificates S3 bucket"
  value       = aws_s3_bucket.tls_certificates.id
}

output "tls_certificates_bucket_arn" {
  description = "ARN of the TLS certificates S3 bucket"
  value       = aws_s3_bucket.tls_certificates.arn
}