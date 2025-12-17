data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

locals {
  oidc_provider_url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
  oidc_provider_url_without_protocol = replace(local.oidc_provider_url, "https://", "")
}

