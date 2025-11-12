#!/usr/bin/env bash
# TensorRT-LLM NGC-Based Build Script
# Replaces: build_trtllm.sh (custom multi-stage build)

set -e

GREEN='\033[0;32m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

TARGET=${1:-runtime}
NGC_BASE="nvcr.io/nvidia/ai-dynamo/tensorrtllm-gpt-oss:latest"
TAG="dynamo-trtllm-ngc:${TARGET}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE="$SCRIPT_DIR/Dockerfile.${TARGET}"

print_info "Building TensorRT-LLM NGC-Based ${TARGET}"
print_info "Base: $NGC_BASE"
print_info "Tag: $TAG"

docker pull "$NGC_BASE"

docker build \
    --platform linux/amd64 \
    -t "$TAG" \
    -f "$DOCKERFILE" \
    "$SCRIPT_DIR/.."

print_info "Build complete: $TAG"
print_info "Size: $(docker images $TAG --format '{{.Size}}')"
