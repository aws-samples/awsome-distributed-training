resource "null_resource" "patch_alb_deployment" {
  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${var.eks_cluster_name}
      
      for i in {1..20}; do
        if kubectl get deployment hyperpod-inference-operator-alb -n kube-system >/dev/null 2>&1; then
          kubectl patch deployment hyperpod-inference-operator-alb -n kube-system -p '{
            "spec": {
              "template": {
                "spec": {
                  "tolerations": [
                    {
                      "key": "sagemaker.amazonaws.com/node-health-status",
                      "operator": "Equal",
                      "value": "Unschedulable", 
                      "effect": "NoSchedule"
                    }
                  ]
                }
              }
            }
          }'
          exit 0
        fi
        sleep 30
      done
    EOT
  }
  depends_on = [helm_release.inference_operator]
}
