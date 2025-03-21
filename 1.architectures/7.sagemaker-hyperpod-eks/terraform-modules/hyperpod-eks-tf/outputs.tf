# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = var.create_vpc ? module.vpc[0].vpc_id : var.existing_vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = var.create_vpc ? module.vpc[0].vpc_cidr : null
}

output "public_subnet_1_id" {
  description = "ID of the first public subnet"
  value       = var.create_vpc ? module.vpc[0].public_subnet_1_id : null
}

output "public_subnet_2_id" {
  description = "ID of the second public subnet"
  value       = var.create_vpc ? module.vpc[0].public_subnet_2_id : null
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = var.create_vpc ? module.vpc[0].nat_gateway_1_id : var.existing_nat_gateway_id
}

# Private Subnet Outputs
output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = var.create_private_subnet ? module.private_subnet[0].private_subnet_id : var.existing_private_subnet_id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = var.create_private_subnet ? module.private_subnet[0].private_route_table_id : var.existing_private_route_table_id
}

# Security Group Outputs
output "security_group_id" {
  description = "ID of the security group"
  value       = var.create_security_group ? module.security_group[0].security_group_id : var.existing_security_group_id
}

# EKS Cluster Outputs
output "eks_cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = var.create_eks ? module.eks_cluster[0].eks_cluster_arn : data.aws_eks_cluster.existing_eks_cluster[0].arn
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = var.create_eks ? module.eks_cluster[0].eks_cluster_name : var.existing_eks_cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  value       = var.create_eks ? module.eks_cluster[0].eks_cluster_endpoint : data.aws_eks_cluster.existing_eks_cluster[0].endpoint
}

output "eks_cluster_certificate_authority" {
  description = "Certificate authority of the EKS cluster"
  value       = var.create_eks ? module.eks_cluster[0].eks_cluster_certificate_authority : data.aws_eks_cluster.existing_eks_cluster[0].certificate_authority[0].data
  sensitive   = true
}

# S3 Bucket Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = var.create_s3_bucket ? module.s3_bucket[0].s3_bucket_name : var.existing_s3_bucket_name
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = var.create_s3_bucket ? module.s3_bucket[0].s3_bucket_arn : data.aws_s3_bucket.existing_s3_bucket[0].arn
}

# S3 Endpoint Outputs
output "s3_endpoint_id" {
  description = "ID of the S3 VPC endpoint"
  value       = var.create_s3_endpoint ? module.s3_endpoint[0].vpc_endpoint_id : null
}

# SageMaker IAM Role Outputs
output "sagemaker_iam_role_arn" {
  description = "ARN of the SageMaker IAM role"
  value       = var.create_sagemaker_iam_role ? module.sagemaker_iam_role[0].sagemaker_iam_role_arn : null
}

output "sagemaker_iam_role_name" {
  description = "Name of the SageMaker IAM role"
  value       = var.create_sagemaker_iam_role ? module.sagemaker_iam_role[0].sagemaker_iam_role_name : var.existing_sagemaker_iam_role_name
}

# Helm Chart Outputs
output "helm_release_name" {
  description = "Name of the Helm release"
  value       = var.create_helm_chart ? module.helm_chart[0].helm_release_name : null
}

output "helm_release_status" {
  description = "Status of the Helm release"
  value       = var.create_helm_chart ? module.helm_chart[0].helm_release_status : null
}

# HyperPod Cluster Outputs
output "hyperpod_cluster_name" {
  description = "Name of the HyperPod cluster"
  value       = var.create_hyperpod ? module.hyperpod_cluster[0].hyperpod_cluster_name : null
}

output "hyperpod_cluster_arn" {
  description = "ARN of the HyperPod cluster"
  value       = var.create_hyperpod ? module.hyperpod_cluster[0].hyperpod_cluster_arn : null
}

output "hyperpod_cluster_status" {
  description = "Status of the HyperPod cluster"
  value       = var.create_hyperpod ? module.hyperpod_cluster[0].hyperpod_cluster_status : null
}

# Region Output
output "aws_region" {
  description = "AWS region"
  value       = data.aws_region.current.name
}
