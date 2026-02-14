variable "project_name" {
  description = "Name of the CodeBuild project"
  type        = string
  default     = "pytorch-fsdp"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "fsdp"
}

variable "github_repository" {
  description = "GitHub repository URL"
  type        = string
  default     = ""
}

variable "github_branch" {
  description = "GitHub branch to build"
  type        = string
  default     = "main"
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "build_timeout" {
  description = "Build timeout in minutes"
  type        = number
  default     = 60

  validation {
    condition     = var.build_timeout >= 5 && var.build_timeout <= 480
    error_message = "Build timeout must be between 5 and 480 minutes."
  }
}

variable "compute_type" {
  description = "CodeBuild compute type"
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_2XLARGE"], var.compute_type)
    error_message = "Compute type must be one of: BUILD_GENERAL1_SMALL, BUILD_GENERAL1_MEDIUM, BUILD_GENERAL1_LARGE, BUILD_GENERAL1_2XLARGE."
  }
}

variable "enable_webhook" {
  description = "Enable GitHub webhook trigger"
  type        = bool
  default     = true
}

variable "enable_scheduled_builds" {
  description = "Enable nightly scheduled builds"
  type        = bool
  default     = true
}

variable "schedule_expression" {
  description = "CloudWatch Events schedule expression (UTC)"
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
