# Data source for current AWS region
data "aws_region" "current" {}

data "aws_iam_role" "sm_studio_role" {
  count = var.using_sm_code_editor ? 1 : 0
  name  = "${var.resource_name_prefix}-SMCE-Exec-Role-${data.aws_region.current.name}"
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = data.aws_vpc.selected.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.resource_name_prefix}-private-subnet-${count.index + 1}"
  }
}


resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.resource_name_prefix}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach managed policy to the role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy_attachment" {
    role = aws_iam_role.eks_cluster_role.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.eks_cluster_name}/cluster"
  retention_in_days = 7
}

resource "aws_eks_cluster" "cluster" {
  name     = var.eks_cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    security_group_ids      = [var.security_group_id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  depends_on = [
    aws_cloudwatch_log_group.eks_cluster,
    aws_iam_role_policy_attachment.cluster_policy,
    aws_subnet.private
  ]
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name      = aws_eks_cluster.cluster.name
  addon_name        = "vpc-cni"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = aws_eks_cluster.cluster.name
  addon_name        = "kube-proxy"
}

resource "aws_eks_addon" "coredns" {
  cluster_name      = aws_eks_cluster.cluster.name
  addon_name        = "coredns"
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name      = aws_eks_cluster.cluster.name
  addon_name        = "eks-pod-identity-agent"
}


resource "aws_eks_access_entry" "sm_code_editor" {
  count = var.using_sm_code_editor ? 1 : 0

  cluster_name  = aws_eks_cluster.cluster.name
  principal_arn = data.aws_iam_role.sm_studio_role[0].arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "sm_code_editor" {
  count = var.using_sm_code_editor ? 1 : 0

  cluster_name  = aws_eks_cluster.cluster.name
  principal_arn = data.aws_iam_role.sm_studio_role[0].arn
  policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.sm_code_editor]
}
