#!/bin/bash
# 3-install-nth.sh — Install AWS Node Termination Handler (IMDS DaemonSet mode)
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/../env_vars"

echo "=== Installing AWS Node Termination Handler ==="
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update eks

helm install nth eks/aws-node-termination-handler \
  --namespace kube-system \
  --set enableSpotInterruptionDraining=true \
  --set enableScheduledEventDraining=true \
  --set nodeTerminationGracePeriod=120

echo ""
echo "=== Verify NTH pods ==="
sleep 10
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-node-termination-handler

echo ""
echo "NTH installed. It will:"
echo "  1. Poll instance metadata for Spot interruption notices"
echo "  2. Cordon the node on notice"
echo "  3. Drain the node (SIGTERM to pods)"
echo "  4. All within the 120s Spot window"
