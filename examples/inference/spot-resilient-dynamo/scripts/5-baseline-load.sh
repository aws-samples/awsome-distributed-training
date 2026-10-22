#!/bin/bash
# 5-baseline-load.sh — Baseline load test (no interruption)
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/../env_vars"

RESULTS_DIR="results/baseline"
mkdir -p "$RESULTS_DIR"

echo "=== Baseline Load Test ==="
echo "Concurrency: 5 | ISL: ~512 | max_tokens: 256 | Duration: 60s"
echo ""

# Port-forward
kubectl port-forward -n "$DYNAMO_NAMESPACE" svc/qwen-spot-frontend 8000:8000 &
PF_PID=$!
sleep 3

# Generate prompts and send requests
START_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Start: $START_TIME"

TOTAL=0
SUCCESS=0
FAIL=0
DURATION=60
END=$((SECONDS + DURATION))
CONCURRENCY=5

send_request() {
  local id=$1
  local result
  result=$(curl -s -o /dev/null -w "%{http_code}" \
    http://localhost:8000/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL_ID\",\"messages\":[{\"role\":\"user\",\"content\":\"Explain distributed computing systems and their role in modern infrastructure in detail. Cover the history, key concepts, architectural patterns, and future directions.\"}],\"max_tokens\":256}" \
    --max-time 120 2>/dev/null)
  echo "$result"
}

echo "Sending requests..."
while [ $SECONDS -lt $END ]; do
  for i in $(seq 1 $CONCURRENCY); do
    CODE=$(send_request $TOTAL)
    TOTAL=$((TOTAL + 1))
    if [ "$CODE" = "200" ]; then
      SUCCESS=$((SUCCESS + 1))
      echo -n "."
    else
      FAIL=$((FAIL + 1))
      echo -n "X"
    fi
  done
done

END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo ""
echo ""
echo "=== Baseline Results ==="
echo "Duration: ${DURATION}s"
echo "Total requests: $TOTAL"
echo "Success (200): $SUCCESS"
echo "Failed: $FAIL"
echo "Success rate: $(echo "scale=1; $SUCCESS * 100 / $TOTAL" | bc)%"
echo "Start: $START_TIME"
echo "End: $END_TIME"

# Save
cat > "$RESULTS_DIR/summary.json" << SUMEOF
{
  "start_time": "$START_TIME",
  "end_time": "$END_TIME",
  "duration_s": $DURATION,
  "concurrency": $CONCURRENCY,
  "total_requests": $TOTAL,
  "success": $SUCCESS,
  "failed": $FAIL,
  "success_rate_pct": $(echo "scale=1; $SUCCESS * 100 / $TOTAL" | bc)
}
SUMEOF

echo "Results saved to $RESULTS_DIR/summary.json"

kill $PF_PID 2>/dev/null
