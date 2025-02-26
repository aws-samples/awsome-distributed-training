output "s3_object_key" {
  description = "The key of the uploaded script in S3"
  value       = aws_s3_object.script.key
}

output "s3_object_version_id" {
  description = "The version ID of the uploaded script (if bucket versioning is enabled)"
  value       = aws_s3_object.script.version_id
}
