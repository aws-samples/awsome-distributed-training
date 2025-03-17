resource "aws_s3_bucket" "bucket" {
  bucket = "${var.resource_name_prefix}-bucket-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_encryption" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Data source for current AWS region
data "aws_region" "current" {}

# Data source for AWS caller identity
data "aws_caller_identity" "current" {}
