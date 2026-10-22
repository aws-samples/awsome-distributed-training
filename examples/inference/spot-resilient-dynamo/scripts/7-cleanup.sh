#!/bin/bash
# 7-cleanup.sh — Scale GPU node to zero (stop Spot charges)
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/../env_vars"

echo "=== Scaling GPU node group to zero ==="

# For self-managed node groups, scale the ASG directly
ASG=$(aws autoscaling describe-auto-scaling-groups --region "$AWS_REGION" \
  --query "AutoScalingGroups[?contains(Tags[?Key=='project'].Value,'dynamo-spot')].AutoScalingGroupName" \
  --output text | head -1)

if [ -n "$ASG" ] && [ "$ASG" != "None" ]; then
  echo "Scaling ASG $ASG to 0..."
  aws autoscaling update-auto-scaling-group --region "$AWS_REGION" \
    --auto-scaling-group-name "$ASG" \
    --desired-capacity 0 --min-size 0
  echo "GPU node group scaled to zero."
else
  echo "No ASG found. Checking for direct-launched instances..."
  INSTANCES=$(aws ec2 describe-instances --region "$AWS_REGION" \
    --filters "Name=tag:project,Values=dynamo-spot" \
              "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].InstanceId" --output text)
  if [ -n "$INSTANCES" ]; then
    echo "Terminating: $INSTANCES"
    aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids $INSTANCES
  else
    echo "No GPU instances running."
  fi
fi

echo ""
echo "System node (m5.large) still running at ~\$0.10/hr."
echo "To delete everything: ./teardown.sh"
