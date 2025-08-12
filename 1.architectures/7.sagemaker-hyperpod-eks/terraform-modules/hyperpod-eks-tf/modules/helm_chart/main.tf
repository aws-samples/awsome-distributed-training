data "aws_region" "current" {}

data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.eks_cluster_name
}

resource "helm_release" "hyperpod" {
  name       = var.helm_release_name
  chart      = "/tmp/helm-repo/${var.helm_repo_path}"
  namespace  = var.namespace
  dependency_update = true
  set = [
    {
      name  = "health-monitoring-agent.region", 
      value = data.aws_region.current.id
    }
  ]
}
