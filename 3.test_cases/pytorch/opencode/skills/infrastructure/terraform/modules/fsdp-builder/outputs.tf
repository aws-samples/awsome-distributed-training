output "codebuild_project_name" {
  description = "CodeBuild Project Name"
  value       = aws_codebuild_project.this.name
}

output "codebuild_project_arn" {
  description = "CodeBuild Project ARN"
  value       = aws_codebuild_project.this.arn
}

output "ecr_repository_uri" {
  description = "ECR Repository URI"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.repository_name}"
}

output "ecr_repository_arn" {
  description = "ECR Repository ARN"
  value       = aws_ecr_repository.this.arn
}

output "artifact_bucket_name" {
  description = "S3 Artifact Bucket Name"
  value       = aws_s3_bucket.artifacts.id
}

output "artifact_bucket_arn" {
  description = "S3 Artifact Bucket ARN"
  value       = aws_s3_bucket.artifacts.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group Name"
  value       = aws_cloudwatch_log_group.this.name
}

output "iam_role_arn" {
  description = "IAM Role ARN"
  value       = aws_iam_role.codebuild.arn
}

output "console_url" {
  description = "AWS Console URL for CodeBuild Project"
  value       = "https://${var.region}.console.aws.amazon.com/codesuite/codebuild/projects/${var.project_name}"
}
