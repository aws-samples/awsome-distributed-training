variable "resource_name_prefix" {
  description = "Prefix to be used for all resources created by this module"
  type        = string
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
}

variable "helm_repo_url" {
  description = "The URL of the Helm repo containing the HyperPod Helm chart"
  type        = string
  default     = "https://github.com/aws/sagemaker-hyperpod-cli.git"
}

variable "helm_repo_path" {
  description = "The path to the HyperPod Helm chart in the Helm repo"
  type        = string
  default     = "helm_chart/HyperPodHelmChart"
}

variable "namespace" {
  description = "The namespace to deploy the HyperPod Helm chart into"
  type        = string
  default     = "kube-system"
}

variable "helm_release_name" {
  description = "The name of the Helm release"
  type        = string
  default     = "hyperpod-dependencies"
}
