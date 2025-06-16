output "file_system_id" {
  description = "Identifier of the file system"
  value       = aws_fsx_lustre_file_system.main.id
}

output "file_system_arn" {
  description = "Amazon Resource Name of the file system"
  value       = aws_fsx_lustre_file_system.main.arn
}

output "dns_name" {
  description = "DNS name for the file system"
  value       = aws_fsx_lustre_file_system.main.dns_name
}

output "mount_name" {
  description = "The value to be used when mounting the filesystem"
  value       = aws_fsx_lustre_file_system.main.mount_name
}

output "network_interface_ids" {
  description = "Set of Elastic Network Interface identifiers from which the file system is accessible"
  value       = aws_fsx_lustre_file_system.main.network_interface_ids
}

output "storage_class_name" {
  description = "Name of the Kubernetes storage class"
  value       = kubernetes_storage_class.fsx_lustre.metadata[0].name
}

output "persistent_volume_name" {
  description = "Name of the Kubernetes persistent volume"
  value       = kubernetes_persistent_volume.fsx_lustre.metadata[0].name
}