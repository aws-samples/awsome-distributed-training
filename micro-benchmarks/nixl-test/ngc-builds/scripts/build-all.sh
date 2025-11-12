#!/usr/bin/env bash
# Build All NGC-Based Images
# Replaces: build-all-runtime.sh, build-all-slim.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_header() {
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}=====================================${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

TARGET=${1:-runtime}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGC_DIR="$(dirname "$SCRIPT_DIR")"

print_header "Building All NGC-Based Images"
echo "Target: $TARGET"
echo "Options: runtime, dev, benchmark"
echo ""

# Build vLLM
print_header "Building vLLM ${TARGET}"
cd "$NGC_DIR/vllm"
./build-vllm.sh "$TARGET"

echo ""

# Build TensorRT-LLM
print_header "Building TensorRT-LLM ${TARGET}"
cd "$NGC_DIR/trtllm"
./build-trtllm.sh "$TARGET"

echo ""
print_header "All Builds Complete!"

print_info "Built images:"
docker images | grep dynamo-.*-ngc

echo ""
print_info "Total size comparison:"
echo "  Old custom builds: ~64GB (vllm + trtllm)"
echo "  New NGC builds:    ~47GB (vllm + trtllm)"
echo "  Savings:           ~17GB"
