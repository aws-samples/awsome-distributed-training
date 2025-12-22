data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

locals {
  oidc_provider_url                  = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
  oidc_provider_url_without_protocol = replace(local.oidc_provider_url, "https://", "")
}

data "tls_certificate" "eks_oidc_thumbprint" {
  url = local.oidc_provider_url
}

resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc_thumbprint.certificates[0].sha1_fingerprint]
  url             = local.oidc_provider_url

  tags = {
    Name = "${var.resource_name_prefix}-eks-oidc-provider"
  }
}
