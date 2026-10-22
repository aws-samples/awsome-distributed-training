#!/bin/bash
# 0-install-platform.sh — Create EKS cluster + install Dynamo platform
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env_vars"

echo "=== Step 1: Create EKS cluster ==="
eksctl create cluster -f "${SCRIPT_DIR}/../manifests/cluster/0-eks-cluster.yaml"

echo ""
echo "=== Step 1b: Update kubeconfig ==="
aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"

echo ""
echo "=== Step 1c: Verify nodes ==="
kubectl get nodes -L role

echo ""
echo "=== Step 1d: Install EBS CSI driver (for etcd/NATS PVCs) ==="
eksctl create addon --name aws-ebs-csi-driver \
  --cluster "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --force

sleep 30

cat <<'SC' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
SC

echo ""
echo "=== Step 1e: Install Dynamo Platform v${DYNAMO_VERSION} ==="
kubectl create namespace "$DYNAMO_NAMESPACE" || true

helm install dynamo-platform \
  "https://helm.ngc.nvidia.com/nvidia/ai-dynamo/charts/dynamo-platform-${DYNAMO_VERSION}.tgz" \
  --namespace "$DYNAMO_NAMESPACE" \
  --set global.etcd.install=true \
  --set global.nats.install=true \
  --wait --timeout 300s

echo ""
echo "=== Verify ==="
kubectl get pods -n "$DYNAMO_NAMESPACE"
kubectl get crd | grep dynamo

echo ""
echo "=== Platform installed ==="
