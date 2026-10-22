#!/bin/bash
# 2-deploy-disaggregated.sh — Deploy the aggregated Dynamo worker
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env_vars"

echo "=== Deploying DynamoGraphDeployment (aggregated) ==="
kubectl apply -f "${SCRIPT_DIR}/../manifests/dynamo/dgd-aggregated.yaml"

echo ""
echo "Waiting for pods to start (model download may take a few minutes)..."
echo "Watch with: kubectl get pods -n $DYNAMO_NAMESPACE -w"
echo ""

# Wait up to 10 minutes for the worker to be ready
kubectl wait --for=condition=Ready pod \
  -l nvidia.com/dynamo-graph-deployment-name=qwen-spot \
  -n "$DYNAMO_NAMESPACE" \
  --timeout=600s || {
    echo "Pods not ready after 10 min. Check: kubectl get pods -n $DYNAMO_NAMESPACE"
    kubectl get pods -n "$DYNAMO_NAMESPACE"
    exit 1
  }

echo ""
echo "=== Pods Ready ==="
kubectl get pods -n "$DYNAMO_NAMESPACE"

echo ""
echo "=== Smoke test ==="
kubectl port-forward -n "$DYNAMO_NAMESPACE" svc/qwen-spot-frontend 8000:8000 &
PF_PID=$!
sleep 3

curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL_ID\",\"messages\":[{\"role\":\"user\",\"content\":\"What is 2+2? Reply in one word.\"}],\"max_tokens\":10}" \
  | python3 -m json.tool

kill $PF_PID 2>/dev/null
echo ""
echo "=== Deployment complete ==="
