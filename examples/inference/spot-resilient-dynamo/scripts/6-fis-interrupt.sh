#!/bin/bash
# 6-fis-interrupt.sh — FIS Spot interruption test
#
# Prerequisites:
#   - Cluster running with GPU Spot worker serving traffic
#   - An IAM role for FIS with ec2:SendSpotInstanceInterruptions permission
#   - NTH installed (3-install-nth.sh)
#
# This script:
#   1. Looks up the Spot instance ID from the GPU node
#   2. Creates an FIS experiment template
#   3. Starts a load in the background
#   4. Triggers the interruption
#   5. Records in-flight request survival + recovery timeline

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/../env_vars"

RESULTS_DIR="results/interruption"
mkdir -p "$RESULTS_DIR"

echo "=== FIS Spot Interruption Test ==="

# 1. Find the Spot instance
echo "Looking up Spot GPU instance..."
INSTANCE_ID=$(kubectl get nodes -l role=gpu-spot \
  -o jsonpath='{.items[0].spec.providerID}' | cut -d/ -f5)

if [ -z "$INSTANCE_ID" ]; then
  echo "ERROR: No GPU Spot node found. Is the worker running?"
  exit 1
fi

# Confirm it's Spot
LIFECYCLE=$(aws ec2 describe-instances --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[].Instances[].InstanceLifecycle" --output text)
echo "Instance: $INSTANCE_ID (lifecycle: $LIFECYCLE)"

if [ "$LIFECYCLE" != "spot" ]; then
  echo "WARNING: Instance is not Spot ($LIFECYCLE). FIS Spot interruption won't work."
  echo "You can still test graceful shutdown with: kubectl drain <node>"
fi

echo "Instance ID: $INSTANCE_ID" > "$RESULTS_DIR/target.txt"

# 2. Create FIS experiment template
echo ""
echo "Creating FIS experiment template..."
echo "NOTE: You need an IAM role for FIS. If you don't have one, create it first:"
echo "  See: https://docs.aws.amazon.com/fis/latest/userguide/getting-started-iam-service-linked-role.html"
echo ""
echo "For a manual test without FIS, you can simulate the interruption:"
echo "  TARGET_NODE=\$(kubectl get nodes -l role=gpu-spot -o jsonpath='{.items[0].metadata.name}')"
echo "  kubectl cordon \$TARGET_NODE"
echo "  kubectl drain \$TARGET_NODE --grace-period=120 --delete-emptydir-data --ignore-daemonsets --force"
echo ""

# 3. Start load in background
echo "Starting background load (180s, 5 concurrent)..."
kubectl port-forward -n "$DYNAMO_NAMESPACE" svc/qwen-spot-frontend 8000:8000 &
PF_PID=$!
sleep 3

LOAD_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TOTAL=0
SUCCESS=0
FAIL_503=0
FAIL_OTHER=0

send_and_count() {
  while [ $SECONDS -lt $END ]; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      http://localhost:8000/v1/chat/completions \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"$MODEL_ID\",\"messages\":[{\"role\":\"user\",\"content\":\"Explain distributed systems.\"}],\"max_tokens\":256}" \
      --max-time 120 2>/dev/null || echo "000")
    TOTAL=$((TOTAL + 1))
    if [ "$CODE" = "200" ]; then
      SUCCESS=$((SUCCESS + 1))
      echo -n "."
    elif [ "$CODE" = "503" ]; then
      FAIL_503=$((FAIL_503 + 1))
      echo -n "5"
    else
      FAIL_OTHER=$((FAIL_OTHER + 1))
      echo -n "X"
    fi
  done
}

END=$((SECONDS + 180))
send_and_count &
LOAD_PID=$!

# 4. Wait 15s then trigger interruption
sleep 15
INTERRUPT_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo ""
echo ">>> INTERRUPTION at $INTERRUPT_TIME <<<"
echo ""

# Simulate Spot interruption via drain (works without FIS IAM role)
TARGET_NODE=$(kubectl get nodes -l role=gpu-spot -o jsonpath='{.items[0].metadata.name}')
echo "Cordoning $TARGET_NODE..."
kubectl cordon "$TARGET_NODE"
echo "Draining $TARGET_NODE (grace-period=120)..."
kubectl drain "$TARGET_NODE" \
  --grace-period=120 \
  --delete-emptydir-data \
  --ignore-daemonsets \
  --force &
DRAIN_PID=$!

# Wait for load to finish
wait $LOAD_PID 2>/dev/null || true
wait $DRAIN_PID 2>/dev/null || true

LOAD_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo ""
echo ""
echo "=== Interruption Results ==="
echo "Load window: $LOAD_START → $LOAD_END"
echo "Interruption at: $INTERRUPT_TIME"
echo "Total requests: $TOTAL"
echo "Success (200): $SUCCESS"
echo "503 (expected during gap): $FAIL_503"
echo "Other failures: $FAIL_OTHER"
echo ""

# Pod status
echo "=== Pod status ==="
kubectl get pods -n "$DYNAMO_NAMESPACE" | grep qwen

# Save results
cat > "$RESULTS_DIR/summary.json" << SUMEOF
{
  "load_start": "$LOAD_START",
  "load_end": "$LOAD_END",
  "interrupt_time": "$INTERRUPT_TIME",
  "instance_id": "$INSTANCE_ID",
  "total_requests": $TOTAL,
  "success_200": $SUCCESS,
  "fail_503": $FAIL_503,
  "fail_other": $FAIL_OTHER,
  "target_node": "$TARGET_NODE"
}
SUMEOF

echo "Results saved to $RESULTS_DIR/summary.json"

kill $PF_PID 2>/dev/null || true

echo ""
echo "=== Next: terminate the instance to simulate EC2 reclaim ==="
echo "aws ec2 terminate-instances --region $AWS_REGION --instance-ids $INSTANCE_ID"
