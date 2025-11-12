#!/usr/bin/env bash
# vLLM NGC-Based Build Script
# Replaces: build_vllm.sh (custom multi-stage build)

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
NGC_BASE="nvcr.io/nvidia/ai-dynamo/vllm-runtime:0.6.1.post1"

if [[ ! "$TARGET" =~ ^(runtime|dev|benchmark)$ ]]; then
    echo "Usage: $0 [runtime|dev|benchmark]"
    echo ""
    echo "Options:"
    echo "  runtime   - Production runtime (~17GB)"
    echo "  dev       - Development image (~18GB)"
    echo "  benchmark - With benchmarking (~19GB)"
    exit 1
fi

TAG="dynamo-vllm-ngc:${TARGET}"
DOCKERFILE="$SCRIPT_DIR/Dockerfile.${TARGET}"

print_header "Building vLLM NGC-Based ${TARGET}"

print_info "Old approach: nixl-aligned → dynamo-base → dynamo-vllm (32GB, 45 min)"
print_info "New approach: NGC base → configs (17GB, 5 min)"
echo ""

print_info "Configuration:"
echo "  Base:       $NGC_BASE"
echo "  Target:     $TARGET"
echo "  Dockerfile: $DOCKERFILE"
echo "  Tag:        $TAG"
echo ""

if [[ ! -f "$DOCKERFILE" ]]; then
    echo "ERROR: Dockerfile not found: $DOCKERFILE"
    exit 1
fi

print_info "Pulling NGC base image..."
docker pull "$NGC_BASE"

print_info "Building image..."
docker build \
    --platform linux/amd64 \
    -t "$TAG" \
    -f "$DOCKERFILE" \
    "$SCRIPT_DIR/.."

print_header "Build Complete!"
print_info "Image: $TAG"
print_info "Size: $(docker images $TAG --format '{{.Size}}')"
echo ""
print_info "vs custom build: dynamo-vllm:slim (32GB)"
print_info "Savings: ~15GB (47% smaller)"
echo ""
print_info "Next steps:"
echo "  Test:   docker run --rm $TAG python3 -c 'import vllm; print(vllm.__version__)'"
echo "  Deploy: kubectl apply -f ../../configs/vllm-disagg.yaml"
