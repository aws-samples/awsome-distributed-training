resource "aws_fsx_openzfs_file_system" "main" {
  storage_capacity    = var.storage_capacity
  subnet_ids          = [var.private_subnet_id]
  security_group_ids  = [var.security_group_id]
  deployment_type     = "SINGLE_AZ_1"
  throughput_capacity = var.throughput_capacity

  root_volume_configuration {
    data_compression_type = var.compression_type
    nfs_exports {
      client_configurations {
        clients = "*"
        options = ["rw", "crossmnt"]
      }
    }
  }

  tags = {
    Name = "${var.resource_name_prefix}-fsx-openzfs"
  }
}
