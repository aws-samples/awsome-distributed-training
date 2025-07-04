output "role_arn" {
  description = "ARN of the IAM role for S3 Mountpoint CSI driver"
  value       = aws_iam_role.s3_mountpoint.arn
}

output "service_account_arn" {
  description = "ARN of the Kubernetes service account"
  value       = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.s3_mountpoint.name}"
}

output "service_account_name" {
  description = "Name of the Kubernetes service account"
  value       = kubernetes_service_account.s3_mountpoint.metadata[0].name
}

output "storage_class_name" {
  description = "Name of the S3 Mountpoint storage class"
  value       = kubernetes_storage_class.s3_mountpoint.metadata[0].name
}

data "aws_caller_identity" "current" {}