output "region" {
  description = "AWS region"
  value       = var.region
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks.cluster_oidc_issuer_url
}

output "cluster_version" {
  description = "The Kubernetes version for the EKS cluster"
  value       = module.eks.cluster_version
}

output "vpc_id" {
  description = "ID of the VPC where the cluster is deployed"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "node_security_group_id" {
  description = "ID of the node shared security group"
  value       = module.eks.node_security_group_id
}

output "eks_managed_node_groups" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = module.eks.eks_managed_node_groups
}

output "fsx_lustre_id" {
  description = "FSx Lustre file system ID"
  value       = module.fsx_lustre.file_system_id
}

output "fsx_lustre_mount_name" {
  description = "FSx Lustre mount name"
  value       = module.fsx_lustre.mount_name
}

output "fsx_lustre_dns_name" {
  description = "FSx Lustre DNS name"
  value       = module.fsx_lustre.dns_name
}

output "s3_mountpoint_service_account_arn" {
  description = "ARN of the S3 Mountpoint service account"
  value       = module.s3_mountpoint.service_account_arn
}

output "s3_mountpoint_role_arn" {
  description = "ARN of the S3 Mountpoint IAM role"
  value       = module.s3_mountpoint.role_arn
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "node_health_dashboard_url" {
  description = "URL of the CloudWatch dashboard for node health monitoring"
  value       = module.addons.node_health_dashboard_url
}

output "node_health_sns_topic_arn" {
  description = "ARN of the SNS topic for node health alerts"
  value       = module.addons.node_health_sns_topic_arn
}

output "karpenter_role_arn" {
  description = "ARN of the Karpenter IAM role"
  value       = module.addons.karpenter_role_arn
}

output "karpenter_instance_profile_name" {
  description = "Name of the Karpenter node instance profile"
  value       = module.addons.karpenter_instance_profile_name
}

output "karpenter_queue_name" {
  description = "Name of the Karpenter SQS queue for spot instance interruption handling"
  value       = module.addons.karpenter_queue_name
}