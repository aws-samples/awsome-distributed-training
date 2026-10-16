
#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="${1:?Usage: $0 <gateway-endpoint>}"
MODEL="Qwen/Qwen2.5-7B-Instruct"
PASSED=0
FAILED=0

echo "============================================="
echo " Inference Gateway — Routing Test Suite"
echo " Endpoint: ${ENDPOINT}"
echo " Model:    ${MODEL}"
echo "============================================="
echo ""

run_test() {
  local test_name="$1"
  local payload="$2"
  local streaming="${3:-false}"

  echo ">>> ${test_name}"

  if [ "$streaming" = "true" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 60 \
      -X POST "${ENDPOINT}/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -d "${payload}")
  else
    RESPONSE=$(curl -s --max-time 60 \
      -X POST "${ENDPOINT}/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -d "${payload}")
    HTTP_CODE=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'choices' in d:
        print('200')
    else:
        print('500')
except:
    print('500')
" 2>/dev/null || echo "500")
  fi

  if [ "$HTTP_CODE" = "200" ]; then
    echo "  ✅ HTTP 200"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ HTTP ${HTTP_CODE}"
    FAILED=$((FAILED + 1))
  fi
  echo ""
}

# Test 1: Basic chat completion
run_test "Test 1: Qwen2.5 7B — Basic Chat" '{
  "model": "'"${MODEL}"'",
  "messages": [{"role": "user", "content": "Explain what an inference gateway does in two sentences."}],
  "max_tokens": 100
}'

# Test 2: Follow-up question
run_test "Test 2: Qwen2.5 7B — Follow-up" '{
  "model": "'"${MODEL}"'",
  "messages": [
    {"role": "user", "content": "What is KV caching in LLM inference?"}
  ],
  "max_tokens": 100
}'

# Test 3: System prompt
run_test "Test 3: Qwen2.5 7B — System Prompt" '{
  "model": "'"${MODEL}"'",
  "messages": [
    {"role": "system", "content": "You are a helpful AWS solutions architect."},
    {"role": "user", "content": "When should I use SageMaker HyperPod vs a standard EKS deployment for LLM inference?"}
  ],
  "max_tokens": 150
}'

# Test 4: Streaming
run_test "Test 4: Qwen2.5 7B — Streaming" '{
  "model": "'"${MODEL}"'",
  "messages": [{"role": "user", "content": "List three benefits of model inference gateways."}],
  "max_tokens": 100,
  "stream": true
}' "true"

echo "============================================="
echo " Results: ${PASSED} passed, ${FAILED} failed"
echo "============================================="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi

