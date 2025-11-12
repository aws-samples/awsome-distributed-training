#!/usr/bin/env bash
# Deploy NGC-Based Images to Kubernetes

set -e

GREEN='\033[0;32m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

DEPLOYMENT=${1:-standalone}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/configs"

if [[ ! "$DEPLOYMENT" =~ ^(standalone|disagg)$ ]]; then
    echo "Usage: $0 [standalone|disagg]"
    echo ""
    echo "Options:"
    echo "  standalone - Simple single-pod deployment"
    echo "  disagg     - Disaggregated prefill/decode"
    exit 1
fi

if [ "$DEPLOYMENT" = "standalone" ]; then
    CONFIG="$CONFIG_DIR/vllm-standalone.yaml"
    print_info "Deploying vLLM standalone..."
else
    CONFIG="$CONFIG_DIR/vllm-disagg.yaml"
    print_info "Deploying vLLM disaggregated..."
fi

kubectl apply -f "$CONFIG"

print_info "Deployment applied. Check status:"
if [ "$DEPLOYMENT" = "standalone" ]; then
    echo "  kubectl get pod dynamo-vllm-ngc"
    echo "  kubectl logs dynamo-vllm-ngc --tail=50"
else
    echo "  kubectl get pods -n dynamo-cloud"
    echo "  kubectl logs -n dynamo-cloud -l app=vllm-disagg-ngc"
fi
