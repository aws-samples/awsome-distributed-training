#!/bin/bash
set -e

REGION=$1
EKS_CLUSTER_NAME=$2

aws eks update-kubeconfig --region $REGION --name $EKS_CLUSTER_NAME

echo "Waiting for cert-manager deployments to be ready..."
deployments=("cert-manager" "cert-manager-cainjector" "cert-manager-webhook")

for deployment in "${deployments[@]}"; do
  echo "Checking deployment: $deployment"
  for i in {1..30}; do
    ready_replicas=$(kubectl get deployment $deployment -n cert-manager -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$ready_replicas" -gt 0 ]; then
      echo "Deployment $deployment is ready with $ready_replicas replicas"
      break
    fi
    echo "Deployment $deployment not ready yet, waiting... ($i/30)"
    sleep 10
  done
  
  # Final check
  ready_replicas=$(kubectl get deployment $deployment -n cert-manager -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  if [ "$ready_replicas" -eq 0 ]; then
    echo "Error: Deployment $deployment is not ready after 5 minutes"
    exit 1
  fi
done

echo "All cert-manager deployments are ready"
