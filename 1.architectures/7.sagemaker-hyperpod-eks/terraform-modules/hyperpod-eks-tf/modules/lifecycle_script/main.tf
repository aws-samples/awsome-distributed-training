data "http" "script" {
  url = var.script_url
}

resource "aws_s3_object" "script" {
  bucket       = var.s3_bucket_name
  key          = "on_create.sh"
  content      = data.http.script.response_body
  content_type = "text/x-sh"
}
