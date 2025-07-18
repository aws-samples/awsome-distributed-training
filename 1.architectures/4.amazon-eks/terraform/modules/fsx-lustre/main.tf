resource "aws_fsx_lustre_file_system" "main" {
  storage_capacity            = var.storage_capacity
  subnet_ids                  = var.subnet_ids
  deployment_type             = var.deployment_type
  per_unit_storage_throughput = var.per_unit_storage_throughput
  security_group_ids          = var.security_group_ids

  dynamic "log_configuration" {
    for_each = var.log_configuration != null ? [var.log_configuration] : []
    content {
      destination = log_configuration.value.destination
      level       = log_configuration.value.level
    }
  }

  import_path = var.s3_import_path
  export_path = var.s3_export_path

  # Auto import and export configuration
  auto_import_policy = var.auto_import_policy
  
  # Data compression
  data_compression_type = var.data_compression_type

  # Copy tags to snapshots
  copy_tags_to_backups = var.copy_tags_to_backups

  # Weekly maintenance window
  weekly_maintenance_start_time = var.weekly_maintenance_start_time

  # Backup configuration for PERSISTENT deployments
  dynamic "backup_configuration" {
    for_each = var.deployment_type == "PERSISTENT_1" || var.deployment_type == "PERSISTENT_2" ? [1] : []
    content {
      automatic_backup_retention_days = var.automatic_backup_retention_days
      daily_automatic_backup_start_time = var.daily_automatic_backup_start_time
    }
  }

  tags = merge(var.tags, {
    Name = var.name
  })
}

# Create CSI driver for FSx Lustre
resource "kubernetes_storage_class" "fsx_lustre" {
  metadata {
    name = "fsx-lustre-sc"
  }
  
  storage_provisioner = "fsx.csi.aws.com"
  
  parameters = {
    subPath = "/"
    dnsName = aws_fsx_lustre_file_system.main.dns_name
    mountName = aws_fsx_lustre_file_system.main.mount_name
  }
  
  mount_options = [
    "flock"
  ]
}

# Create a persistent volume for FSx Lustre
resource "kubernetes_persistent_volume" "fsx_lustre" {
  metadata {
    name = "fsx-lustre-pv"
  }
  
  spec {
    capacity = {
      storage = "${var.storage_capacity}Gi"
    }
    
    access_modes = ["ReadWriteMany"]
    
    persistent_volume_source {
      csi {
        driver        = "fsx.csi.aws.com"
        volume_handle = aws_fsx_lustre_file_system.main.id
        
        volume_attributes = {
          dnsName   = aws_fsx_lustre_file_system.main.dns_name
          mountName = aws_fsx_lustre_file_system.main.mount_name
        }
      }
    }
    
    storage_class_name = kubernetes_storage_class.fsx_lustre.metadata[0].name
  }
}

# Example PVC for FSx Lustre
resource "kubernetes_persistent_volume_claim" "fsx_lustre_example" {
  count = var.create_example_pvc ? 1 : 0
  
  metadata {
    name      = "fsx-lustre-pvc"
    namespace = var.example_namespace
  }
  
  spec {
    access_modes = ["ReadWriteMany"]
    
    resources {
      requests = {
        storage = "100Gi"
      }
    }
    
    storage_class_name = kubernetes_storage_class.fsx_lustre.metadata[0].name
    volume_name        = kubernetes_persistent_volume.fsx_lustre.metadata[0].name
  }
}