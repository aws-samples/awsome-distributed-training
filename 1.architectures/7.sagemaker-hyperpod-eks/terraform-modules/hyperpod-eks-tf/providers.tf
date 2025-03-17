provider "aws" {
  region = "us-west-2" # Adjust as needed
}

provider "awscc" {
  region = "us-west-2"
}

provider "helm" {
  kubernetes {
    host                   = var.create_eks ? module.eks_cluster[0].eks_cluster_endpoint :  data.aws_eks_cluster.existing_eks_cluster[0].endpoint
    cluster_ca_certificate = base64decode(var.create_eks ? module.eks_cluster[0].eks_cluster_certificate_authority : data.aws_eks_cluster.existing_eks_cluster[0].certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", var.create_eks ? module.eks_cluster[0].eks_cluster_name : var.eks_cluster_name]
      command     = "aws"
    }
  }
}

provider "null" {}