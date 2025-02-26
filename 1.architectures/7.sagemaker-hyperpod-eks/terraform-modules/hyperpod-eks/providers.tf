provider "aws" {
  region = "us-west-2" # Adjust as needed
}

provider "awscc" {
  region = "us-west-2"
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                 = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "null" {}