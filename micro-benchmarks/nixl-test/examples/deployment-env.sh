#!/usr/bin/env bash
# deployment-env.sh - Environment configuration for vLLM deployment
# Source this file before deploying or running benchmarks: source examples/deployment-env.sh

# Kubernetes Configuration
export NAMESPACE="dynamo-cloud"
export DEPLOYMENT_BASE_NAME="llama-fp8-benchmark"
export DEPLOYMENT_NAME="${DEPLOYMENT_BASE_NAME}"
export FRONTEND_NAME="Frontend"
export WORKER_NAME="VllmWorker"
export FRONTEND_SVC="${DEPLOYMENT_NAME}-frontend"
export RELEASE_VERSION="0.4.0"

# Model Configuration
export MODEL_ID="meta-llama/Llama-3.3-70B-Instruct"
export MODEL_DIR="/models/llama-3.3-70b"
export CACHE_DIR="/models/.cache"

# Hardware & Parallelism Configuration
export TENSOR_PARALLEL_SIZE="8"

# Memory & Context Configuration
export MAX_MODEL_LEN="131072"
export GPU_MEMORY_UTILIZATION="0.90"
export KV_CACHE_DTYPE="fp8"
export BLOCK_SIZE="32"

# Concurrency Configuration
export MAX_NUM_SEQS="64"
export MAX_NUM_SEQS_PREFILL="1"
export MAX_NUM_SEQS_DECODE="64"

# Performance Features
export ENABLE_PREFIX_CACHING="true"
export TRUST_REMOTE_CODE="true"
export DISABLE_LOG_REQUESTS="true"

# Observability Configuration
export METRICS_PORT="9091"

# Download Configuration
export MAX_DOWNLOAD_WORKERS="16"
export USE_SYMLINKS="false"

# Node selector (adjust for your cluster)
export NODE_SELECTOR="node.kubernetes.io/instance-type: ml.p5.48xlarge"

# Benchmark Configuration
export LOCAL_PORT="8080"
export TOKENIZER="hf-internal-testing/llama-tokenizer"
export VLLM_URL="http://0.0.0.0:${LOCAL_PORT}"

# Artifact directories
export ARTIFACT_DIR="artifacts"
export EXPORT_DIR="exports"

# Re-export pod names (run after deployment)
export FRONTEND_POD=$(kubectl get pods -n $NAMESPACE 2>/dev/null | grep "^${DEPLOYMENT_NAME}-frontend-" | head -1 | awk '{print $1}')
export WORKER_POD=$(kubectl get pods -n $NAMESPACE 2>/dev/null | grep "^${DEPLOYMENT_NAME}-vllmworker-" | head -1 | awk '{print $1}')

echo "✅ Environment loaded for deployment: $DEPLOYMENT_NAME in namespace: $NAMESPACE"
echo "📦 Model: $MODEL_ID"
echo "🔧 Tensor Parallel Size: $TENSOR_PARALLEL_SIZE"
echo "💾 Max Model Length: $MAX_MODEL_LEN"
echo "🎯 Max Num Seqs: $MAX_NUM_SEQS"

if [ -n "$FRONTEND_POD" ]; then
    echo "🟢 Frontend Pod: $FRONTEND_POD"
fi
if [ -n "$WORKER_POD" ]; then
    echo "🟢 Worker Pod: $WORKER_POD"
fi
