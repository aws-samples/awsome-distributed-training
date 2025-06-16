variable "name" {
  description = "Name of the FSx Lustre file system"
  type        = string
}

variable "storage_capacity" {
  description = "Storage capacity (GiB) of the file system"
  type        = number
  validation {
    condition     = var.storage_capacity >= 1200 && var.storage_capacity % 1200 == 0
    error_message = "Storage capacity must be at least 1200 GiB and in increments of 1200 GiB."
  }
}

variable "subnet_ids" {
  description = "List of subnet IDs for the file system"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for the file system"
  type        = list(string)
}

variable "deployment_type" {
  description = "Deployment type for the file system"
  type        = string
  default     = "SCRATCH_2"
  validation {
    condition     = contains(["SCRATCH_1", "SCRATCH_2", "PERSISTENT_1", "PERSISTENT_2"], var.deployment_type)
    error_message = "Valid values for deployment_type are SCRATCH_1, SCRATCH_2, PERSISTENT_1, or PERSISTENT_2."
  }
}

variable "per_unit_storage_throughput" {
  description = "Per unit storage throughput (MB/s/TiB)"
  type        = number
  default     = null
}

variable "s3_import_path" {
  description = "S3 URI for importing data"
  type        = string
  default     = null
}

variable "s3_export_path" {
  description = "S3 URI for exporting data"
  type        = string
  default     = null
}

variable "auto_import_policy" {
  description = "How Amazon FSx keeps your file and directory listings up to date"
  type        = string
  default     = "NEW_CHANGED"
  validation {
    condition     = contains(["NONE", "NEW", "NEW_CHANGED", "NEW_CHANGED_DELETED"], var.auto_import_policy)
    error_message = "Valid values are NONE, NEW, NEW_CHANGED, or NEW_CHANGED_DELETED."
  }
}

variable "data_compression_type" {
  description = "Sets the data compression configuration for the file system"
  type        = string
  default     = "NONE"
  validation {
    condition     = contains(["NONE", "LZ4"], var.data_compression_type)
    error_message = "Valid values are NONE or LZ4."
  }
}

variable "copy_tags_to_backups" {
  description = "A boolean flag indicating whether tags for the file system should be copied to backups"
  type        = bool
  default     = false
}

variable "weekly_maintenance_start_time" {
  description = "The preferred start time (in d:HH:MM format) to perform weekly maintenance"
  type        = string
  default     = "1:02:00"
}

variable "automatic_backup_retention_days" {
  description = "The number of days to retain automatic backups"
  type        = number
  default     = 7
}

variable "daily_automatic_backup_start_time" {
  description = "The preferred time (in HH:MM format) to take daily automatic backups"
  type        = string
  default     = "02:00"
}

variable "log_configuration" {
  description = "The Lustre logging configuration"
  type = object({
    destination = string
    level       = string
  })
  default = null
}

variable "create_example_pvc" {
  description = "Whether to create an example PVC"
  type        = bool
  default     = false
}

variable "example_namespace" {
  description = "Namespace for example resources"
  type        = string
  default     = "default"
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}