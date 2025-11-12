#!/usr/bin/env bash
# benchmark-genai-perf.sh - Run GenAI-Perf benchmarks against vLLM deployment
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
NUM_PROMPTS="${NUM_PROMPTS:-330}"
WARMUP_REQUESTS="${WARMUP_REQUESTS:-10}"
REQUEST_COUNT="${REQUEST_COUNT:-320}"
INPUT_TOKENS_MEAN="${INPUT_TOKENS_MEAN:-102400}"
INPUT_TOKENS_STDDEV="${INPUT_TOKENS_STDDEV:-0}"
OUTPUT_TOKENS_MEAN="${OUTPUT_TOKENS_MEAN:-500}"
OUTPUT_TOKENS_STDDEV="${OUTPUT_TOKENS_STDDEV:-500}"
MEASUREMENT_INTERVAL="${MEASUREMENT_INTERVAL:-300000}"
CONCURRENCY="${CONCURRENCY:-16}"
ENDPOINT_TYPE="${ENDPOINT_TYPE:-chat}"

# Create artifact directories
mkdir -p "${ARTIFACT_DIR}/standard"
mkdir -p "${EXPORT_DIR}"

PROFILE_EXPORT="${EXPORT_DIR}/${DEPLOYMENT_NAME}_c${CONCURRENCY}.json"

echo "🧪 Starting GenAI-Perf Benchmark"
echo "================================"
echo "Server URL: $VLLM_URL"
echo "Model: $MODEL_ID"
echo "Input Tokens: ${INPUT_TOKENS_MEAN} ± ${INPUT_TOKENS_STDDEV}"
echo "Output Tokens: ${OUTPUT_TOKENS_MEAN} ± ${OUTPUT_TOKENS_STDDEV}"
echo "Concurrency: $CONCURRENCY"
echo "Num Prompts: $NUM_PROMPTS"
echo "================================"

# Check if server is accessible
if ! curl -sf "${VLLM_URL}/health" > /dev/null 2>&1; then
    echo "⚠️  Warning: Server at ${VLLM_URL} not accessible"
    echo "Make sure port-forward is running:"
    echo "  kubectl port-forward svc/${FRONTEND_SVC} ${LOCAL_PORT}:8080 -n ${NAMESPACE}"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Run GenAI-Perf in Docker container
echo "🚀 Launching GenAI-Perf container..."

docker run --rm --net=host \
  -v "${PWD}/${ARTIFACT_DIR}:/workspace/${ARTIFACT_DIR}" \
  -v "${PWD}/${EXPORT_DIR}:/workspace/${EXPORT_DIR}" \
  nvcr.io/nvidia/tritonserver:${RELEASE_VERSION}-py3-sdk \
  genai-perf profile \
    -m "$MODEL_ID" \
    --endpoint-type "$ENDPOINT_TYPE" \
    --url "$VLLM_URL" \
    --num-prompts "$NUM_PROMPTS" \
    --synthetic-input-tokens-mean "$INPUT_TOKENS_MEAN" \
    --synthetic-input-tokens-stddev "$INPUT_TOKENS_STDDEV" \
    --output-tokens-mean "$OUTPUT_TOKENS_MEAN" \
    --output-tokens-stddev "$OUTPUT_TOKENS_STDDEV" \
    --extra-inputs min_tokens:500 \
    --extra-inputs max_tokens:1000 \
    --extra-inputs ignore_eos:true \
    --random-seed 0 \
    --num-dataset-entries "${NUM_PROMPTS}" \
    --request-count "$REQUEST_COUNT" \
    --warmup-request-count "${WARMUP_REQUESTS}" \
    --concurrency "$CONCURRENCY" \
    --tokenizer "$TOKENIZER" \
    --artifact-dir "${ARTIFACT_DIR}/standard" \
    --profile-export-file "$PROFILE_EXPORT" \
    --generate-plots

echo ""
echo "✅ Benchmark completed!"
echo ""
echo "📊 Results:"
echo "   Artifacts: ${ARTIFACT_DIR}/standard/"
echo "   Profile: ${PROFILE_EXPORT}"
echo ""
echo "📈 View results:"
echo "   ls -lh ${ARTIFACT_DIR}/standard/"
echo "   cat ${PROFILE_EXPORT} | jq '.'"
echo ""

# Display key metrics if jq is available
if command -v jq &> /dev/null && [ -f "$PROFILE_EXPORT" ]; then
    echo "🎯 Key Metrics:"
    jq -r '
        "   TTFT p99: " + (.ttft_p99 | tostring) + "ms",
        "   ITL p50: " + (.itl_p50 | tostring) + "ms",
        "   Request Throughput: " + (.request_throughput | tostring) + " req/s",
        "   Output Token Throughput: " + (.output_token_throughput | tostring) + " tokens/s"
    ' "$PROFILE_EXPORT" 2>/dev/null || echo "   (Metrics in JSON file)"
    echo ""
fi

echo "💾 To save results:"
echo "   tar czf benchmark-results-\$(date +%Y%m%d-%H%M%S).tar.gz ${ARTIFACT_DIR} ${EXPORT_DIR}"
