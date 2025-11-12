#!/usr/bin/env bash
# Test All NGC-Based Images

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

FAILURES=0

# Test vLLM
print_test "Testing dynamo-vllm-ngc:runtime..."
if docker run --rm dynamo-vllm-ngc:runtime bash -c "source /opt/dynamo/venv/bin/activate && python3 -c 'import vllm; import nixl; import dynamo; print(\"OK\")'"; then
    print_pass "vLLM image OK"
else
    print_fail "vLLM image failed"
    ((FAILURES++))
fi

# Test TensorRT-LLM (if exists)
if docker images | grep -q dynamo-trtllm-ngc; then
    print_test "Testing dynamo-trtllm-ngc:runtime..."
    if docker run --rm dynamo-trtllm-ngc:runtime bash -c "python3 -c 'import nixl; import dynamo; print(\"OK\")'"; then
        print_pass "TensorRT-LLM image OK"
    else
        print_fail "TensorRT-LLM image failed"
        ((FAILURES++))
    fi
fi

echo ""
if [ $FAILURES -eq 0 ]; then
    print_pass "All tests passed!"
    exit 0
else
    print_fail "$FAILURES test(s) failed"
    exit 1
fi
