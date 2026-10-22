#!/bin/bash
# teardown.sh — Delete the entire EKS cluster and all resources
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/../env_vars"

echo "=== TEARDOWN: Deleting cluster $EKS_CLUSTER_NAME ==="
echo "This will delete ALL resources: nodes, volumes, load balancers, etc."
echo ""
read -p "Are you sure? (yes/no): " CONFIRM
[ "$CONFIRM" = "yes" ] || { echo "Aborted."; exit 0; }

# Terminate any direct-launched GPU instances first
INSTANCES=$(aws ec2 describe-instances --region "$AWS_REGION" \
  --filters "Name=tag:project,Values=dynamo-spot" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" --output text)
if [ -n "$INSTANCES" ]; then
  echo "Terminating GPU instances: $INSTANCES"
  aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids $INSTANCES
  sleep 30
fi

# Delete Helm releases
echo "Removing Helm releases..."
helm uninstall kube-prometheus -n monitoring 2>/dev/null || true
helm uninstall nth -n kube-system 2>/dev/null || true
helm uninstall dynamo-platform -n dynamo 2>/dev/null || true

# Delete the cluster
echo "Deleting EKS cluster..."
eksctl delete cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"

echo ""
echo "=== Cluster deleted. All charges stopped. ==="
