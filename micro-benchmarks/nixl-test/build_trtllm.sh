#!/bin/bash

set -e

# Configuration
NIXL_BASE_IMAGE="${NIXL_BASE_IMAGE:-nixl-h100-efa:production}"
DYNAMO_BASE_IMAGE="${DYNAMO_BASE_IMAGE:-nvcr.io/nvidia/ai-dynamo/vllm-runtime:0.4.0}"
PYTORCH_IMAGE="${PYTORCH_IMAGE:-nvcr.io/nvidia/pytorch}"
PYTORCH_IMAGE_TAG="${PYTORCH_IMAGE_TAG:-25.06-py3}"
RUNTIME_IMAGE="${RUNTIME_IMAGE:-nvcr.io/nvidia/cuda}"
RUNTIME_IMAGE_TAG="${RUNTIME_IMAGE_TAG:-12.9.1-runtime-ubuntu24.04}"

# TensorRT-LLM configuration
TENSORRTLLM_VERSION="${TENSORRTLLM_VERSION:-0.17.0}"
TENSORRTLLM_PIP_WHEEL="tensorrt-llm"  # No version pin - uses latest
TENSORRTLLM_INDEX_URL="https://pypi.nvidia.com"
GITHUB_TRTLLM_COMMIT="main"  # Fallback to main branch

# Architecture options
CUDA_ARCH="${CUDA_ARCH:-90}"
CUDA_ARCH_NAME="${CUDA_ARCH_NAME:-H100}"

# Build target (runtime, slim, or dev)
BUILD_TARGET="${BUILD_TARGET:-runtime}"

ARCH_ALT="x86_64"
PYTHON_VERSION="3.12"

TAG="${TAG:-dynamo-trtllm:latest}"

# Change to not pin version:

echo "═══════════════════════════════════════════════════════════════"
echo "Building Dynamo + TensorRT-LLM Container"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  NIXL Base:        $NIXL_BASE_IMAGE"
echo "  Dynamo Base:      $DYNAMO_BASE_IMAGE"
echo "  PyTorch Image:    $PYTORCH_IMAGE:$PYTORCH_IMAGE_TAG"
echo "  Runtime Image:    $RUNTIME_IMAGE:$RUNTIME_IMAGE_TAG"
echo "  GPU Arch:         SM${CUDA_ARCH} (${CUDA_ARCH_NAME})"
echo "  Build Target:     $BUILD_TARGET $(if [ "$BUILD_TARGET" = "slim" ]; then echo "(debloated) 🪶"; fi)"
echo "  TensorRT-LLM:     $TENSORRTLLM_VERSION"
echo "  Tag:              $TAG"
echo ""

# Verify required files exist
echo "Verifying required files..."
REQUIRED_FILES=(
    "container/deps/requirements.txt"
    "container/deps/requirements.test.txt"
    "container/launch_message_trtllm.txt"
    "benchmarks/setup.py"
    "LICENSE"
    "ATTRIBUTION.md"
)

MISSING=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ Missing: $file"
        MISSING=$((MISSING + 1))
    else
        echo "✅ Found: $file"
    fi
done

if [ $MISSING -gt 0 ]; then
    echo ""
    echo "❌ $MISSING required files are missing!"
    echo "Run setup_dynamo_build.sh first to create them."
    exit 1
fi

echo ""
echo "Proceed with build? (y/N) "
read -r REPLY
if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
    echo "Build cancelled."
    exit 0
fi

# Build command
docker build \
    --target "$BUILD_TARGET" \
    --build-arg NIXL_BASE_IMAGE="$NIXL_BASE_IMAGE" \
    --build-arg DYNAMO_BASE_IMAGE="$DYNAMO_BASE_IMAGE" \
    --build-arg PYTORCH_IMAGE="$PYTORCH_IMAGE" \
    --build-arg PYTORCH_IMAGE_TAG="$PYTORCH_IMAGE_TAG" \
    --build-arg RUNTIME_IMAGE="$RUNTIME_IMAGE" \
    --build-arg RUNTIME_IMAGE_TAG="$RUNTIME_IMAGE_TAG" \
    --build-arg CUDA_ARCH="$CUDA_ARCH" \
    --build-arg CUDA_ARCH_NAME="$CUDA_ARCH_NAME" \
    --build-arg TENSORRTLLM_PIP_WHEEL="$TENSORRTLLM_PIP_WHEEL" \
    --build-arg TENSORRTLLM_INDEX_URL="$TENSORRTLLM_INDEX_URL" \
    --build-arg ARCH_ALT="$ARCH_ALT" \
    --build-arg PYTHON_VERSION="$PYTHON_VERSION" \
    --build-arg HAS_TRTLLM_CONTEXT=0 \
    -f Dockerfile.dynamo-trtllm \
    -t "$TAG" \
    .

if [ $? -eq 0 ]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "✅ BUILD SUCCESSFUL"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Image: $TAG"
    echo ""
    echo "Test the container:"
    echo "  docker run --rm $TAG nixl-validate"
    echo "  docker run -it --gpus all --network host $TAG"
    echo ""
else
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "❌ BUILD FAILED"
    echo "═══════════════════════════════════════════════════════════════"
    exit 1
fi
