data "kubernetes_resource" "alb_deployment" {
  api_version = "apps/v1"
  kind        = "Deployment"
  metadata {
    name      = "hyperpod-inference-operator-alb"
    namespace = "kube-system"
  }
  
  depends_on = [helm_release.inference_operator]
}

resource "kubernetes_manifest" "alb_deployment_patch" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "hyperpod-inference-operator-alb"
      namespace = "kube-system"
    }
    spec = {
      template = {
        spec = {
          tolerations = [
            {
              key      = "sagemaker.amazonaws.com/node-health-status"
              operator = "Equal"
              value    = "Unschedulable"
              effect   = "NoSchedule"
            }
          ]
        }
      }
    }
  }
  
  depends_on = [data.kubernetes_resource.alb_deployment]
}
