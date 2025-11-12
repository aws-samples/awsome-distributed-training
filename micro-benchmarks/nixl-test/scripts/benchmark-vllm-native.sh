#!/usr/bin/env bash
# benchmark-vllm-native.sh - Run vLLM native benchmarks with concurrency sweep
set -euo pipefail

# Load environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ ! -f "${PROJECT_ROOT}/examples/deployment-env.sh" ]; then
    echo "❌ Error: deployment-env.sh not found"
    exit 1
fi

source "${PROJECT_ROOT}/examples/deployment-env.sh"

# Benchmark Configuration
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-${LOCAL_PORT}}"
RANDOM_INPUT_LEN="${RANDOM_INPUT_LEN:-102000}"
RANDOM_OUTPUT_LEN="${RANDOM_OUTPUT_LEN:-100}"
RESULT_DIR="${RESULT_DIR:-results}"

# Create results directory
mkdir -p "${RESULT_DIR}"

echo "🧪 Starting vLLM Native Benchmark Sweep"
echo "======================================"
echo "Server: ${HOST}:${PORT}"
echo "Model: $MODEL_ID"
echo "Input Length: ${RANDOM_INPUT_LEN} tokens"
echo "Output Length: ${RANDOM_OUTPUT_LEN} tokens"
echo "======================================"
echo ""

# Check if we're running inside a pod or need to exec into one
if [ -z "${KUBERNETES_SERVICE_HOST:-}" ]; then
    echo "📦 Running from outside cluster - will exec into worker pod"
    if [ -z "$WORKER_POD" ]; then
        echo "❌ Error: WORKER_POD not set. Run: source examples/deployment-env.sh"
        exit 1
    fi
    EXEC_PREFIX="kubectl exec -i $WORKER_POD -n $NAMESPACE -- bash -c"
else
    echo "📦 Running inside cluster"
    EXEC_PREFIX="bash -c"
fi

# Warm-up run
echo "🔥 Running warm-up..."
WARMUP_RESULT="${RESULT_DIR}/vllm_warmup.json"

$EXEC_PREFIX "cd /workspace && python3 benchmarks/benchmark_serving.py \
  --backend vllm \
  --host '$HOST' \
  --port '$PORT' \
  --model '$MODEL_ID' \
  --trust-remote-code \
  --dataset-name random \
  --random-input-len $RANDOM_INPUT_LEN \
  --random-output-len $RANDOM_OUTPUT_LEN \
  --ignore-eos \
  --num-prompts 4 \
  --no-stream \
  --percentile-metrics ttft,tpot,itl,e2el \
  --metric-percentiles 25,50,99 \
  --save-result \
  --result-filename '$WARMUP_RESULT' || true"

echo "✅ Warm-up completed"
echo ""

# Main benchmark sweep
echo "🚀 Starting concurrency sweep (1, 2, 4, 8, 16, 32, 48, 64)..."
echo ""

for N in 1 2 4 8 16 32 48 64; do
    OUT_FILE="${RESULT_DIR}/vllm_benchmark_${RANDOM_INPUT_LEN}in_${RANDOM_OUTPUT_LEN}out_${N}prompts.json"

    echo "📊 Running with ${N} concurrent prompts..."

    $EXEC_PREFIX "cd /workspace && python3 benchmarks/benchmark_serving.py \
      --backend vllm \
      --host '$HOST' \
      --port '$PORT' \
      --model '$MODEL_ID' \
      --trust-remote-code \
      --dataset-name random \
      --random-input-len $RANDOM_INPUT_LEN \
      --random-output-len $RANDOM_OUTPUT_LEN \
      --ignore-eos \
      --num-prompts $N \
      --no-stream \
      --percentile-metrics ttft,tpot,itl,e2el \
      --metric-percentiles 25,50,99 \
      --save-result \
      --result-filename '$OUT_FILE'"

    echo "   ✅ Completed ${N} prompts -> ${OUT_FILE}"
    echo ""
done

echo "✅ Benchmark sweep completed!"
echo ""

# Copy results from pod if running externally
if [ -z "${KUBERNETES_SERVICE_HOST:-}" ]; then
    echo "📥 Copying results from pod..."
    kubectl cp "${WORKER_POD}:/workspace/${RESULT_DIR}" "./${RESULT_DIR}" -n ${NAMESPACE}
    echo "✅ Results copied to ./${RESULT_DIR}/"
fi

echo ""
echo "📊 Results Summary:"
echo "   Location: ${RESULT_DIR}/"
echo "   Files:"
ls -lh "${RESULT_DIR}"/vllm_benchmark_*.json 2>/dev/null || echo "   (No results found - check logs for errors)"
echo ""

# Display key metrics if jq is available
if command -v jq &> /dev/null; then
    echo "🎯 Throughput vs Concurrency:"
    echo "   Concurrency | TTFT p50 (ms) | ITL p50 (ms) | Request Throughput (req/s)"
    echo "   ------------|---------------|--------------|---------------------------"

    for N in 1 2 4 8 16 32 48 64; do
        RESULT_FILE="${RESULT_DIR}/vllm_benchmark_${RANDOM_INPUT_LEN}in_${RANDOM_OUTPUT_LEN}out_${N}prompts.json"
        if [ -f "$RESULT_FILE" ]; then
            jq -r --arg N "$N" '
                "   " + ($N | tonumber | tostring | . + (" " * (11 - length))) +
                " | " + (.ttft_p50 | tostring | . + (" " * (13 - length))) +
                " | " + (.itl_p50 | tostring | . + (" " * (12 - length))) +
                " | " + (.request_throughput | tostring)
            ' "$RESULT_FILE" 2>/dev/null || echo "   ${N}           | (parsing error)"
        fi
    done
    echo ""
fi

echo "💾 To analyze results:"
echo "   cat ${RESULT_DIR}/vllm_benchmark_*.json | jq '.'"
echo ""
echo "💾 To save results:"
echo "   tar czf vllm-benchmark-\$(date +%Y%m%d-%H%M%S).tar.gz ${RESULT_DIR}/"
