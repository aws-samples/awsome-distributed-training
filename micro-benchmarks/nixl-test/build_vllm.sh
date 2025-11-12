#!/bin/bash

set -e

# Configuration
NIXL_BASE_IMAGE="${NIXL_BASE_IMAGE:-nixl-h100-efa:optimized}"
DYNAMO_BASE_IMAGE="${DYNAMO_BASE_IMAGE:-nvcr.io/nvidia/ai-dynamo/vllm-runtime:0.4.0}"
PYTORCH_IMAGE="${PYTORCH_IMAGE:-nvcr.io/nvidia/pytorch}"
PYTORCH_IMAGE_TAG="${PYTORCH_IMAGE_TAG:-25.06-py3}"
RUNTIME_IMAGE="${RUNTIME_IMAGE:-nvcr.io/nvidia/cuda}"
RUNTIME_IMAGE_TAG="${RUNTIME_IMAGE_TAG:-12.8.1-runtime-ubuntu24.04}"

# vLLM configuration
USE_SOURCE_BUILD="${USE_SOURCE_BUILD:-false}"  # Set to "true" to build from source
VLLM_REF="${VLLM_REF:-v0.11.0}"
TORCH_BACKEND="${TORCH_BACKEND:-cu128}"
CUDA_VERSION="${CUDA_VERSION:-12.8}"
# Note: MAX_JOBS only used if USE_SOURCE_BUILD=true
MAX_JOBS="${MAX_JOBS:-8}"

# Architecture options (used for environment, not compilation when using pip)
CUDA_ARCH="${CUDA_ARCH:-90}"
CUDA_ARCH_NAME="${CUDA_ARCH_NAME:-H100}"

# Build acceleration (optional)
USE_SCCACHE="${USE_SCCACHE:-false}"
SCCACHE_BUCKET="${SCCACHE_BUCKET:-}"
SCCACHE_REGION="${SCCACHE_REGION:-}"

# Build target (runtime, slim, or dev)
BUILD_TARGET="${BUILD_TARGET:-runtime}"

ARCH_ALT="x86_64"
PYTHON_VERSION="3.12"

TAG="${TAG:-dynamo-vllm:latest}"

echo "═══════════════════════════════════════════════════════════════"
echo "Building Dynamo + vLLM Container"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  NIXL Base:        $NIXL_BASE_IMAGE"
echo "  Dynamo Base:      $DYNAMO_BASE_IMAGE"
echo "  PyTorch Image:    $PYTORCH_IMAGE:$PYTORCH_IMAGE_TAG"
echo "  Runtime Image:    $RUNTIME_IMAGE:$RUNTIME_IMAGE_TAG"
echo "  GPU Arch:         SM${CUDA_ARCH} (${CUDA_ARCH_NAME})"
echo "  Build Target:     $BUILD_TARGET $(if [ "$BUILD_TARGET" = "slim" ]; then echo "(debloated) 🪶"; fi)"
echo "  vLLM Install:     $(if [ "$USE_SOURCE_BUILD" = "true" ]; then echo "Source build (slow)"; else echo "Pip wheel (FAST ⚡)"; fi)"
echo "  vLLM Version:     $VLLM_REF"
echo "  PyTorch Backend:  $TORCH_BACKEND"
echo "  CUDA Version:     $CUDA_VERSION"
if [ "$USE_SOURCE_BUILD" = "true" ]; then
    echo "  Max Jobs:         $MAX_JOBS"
fi
echo "  Tag:              $TAG"
echo ""

# Verify required files exist
echo "Verifying required files..."
REQUIRED_FILES=(
    "container/deps/requirements.txt"
    "container/deps/requirements.test.txt"
    "container/deps/vllm/install_vllm.sh"
    "container/use-sccache.sh"
    "container/launch_message.txt"
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
    --progress=plain \
    --target "$BUILD_TARGET" \
    --build-arg NIXL_BASE_IMAGE="$NIXL_BASE_IMAGE" \
    --build-arg DYNAMO_BASE_IMAGE="$DYNAMO_BASE_IMAGE" \
    --build-arg PYTORCH_IMAGE="$PYTORCH_IMAGE" \
    --build-arg PYTORCH_IMAGE_TAG="$PYTORCH_IMAGE_TAG" \
    --build-arg RUNTIME_IMAGE="$RUNTIME_IMAGE" \
    --build-arg RUNTIME_IMAGE_TAG="$RUNTIME_IMAGE_TAG" \
    --build-arg CUDA_ARCH="$CUDA_ARCH" \
    --build-arg CUDA_ARCH_NAME="$CUDA_ARCH_NAME" \
    --build-arg USE_SOURCE_BUILD="$USE_SOURCE_BUILD" \
    --build-arg VLLM_REF="$VLLM_REF" \
    --build-arg TORCH_BACKEND="$TORCH_BACKEND" \
    --build-arg CUDA_VERSION="$CUDA_VERSION" \
    --build-arg MAX_JOBS="$MAX_JOBS" \
    --build-arg ARCH_ALT="$ARCH_ALT" \
    --build-arg PYTHON_VERSION="$PYTHON_VERSION" \
    -f Dockerfile.dynamo-vllm \
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
    echo "Start vLLM server:"
    echo "  docker run -it --gpus all -p 8000:8000 $TAG \\"
    echo "    vllm serve meta-llama/Llama-2-7b-hf \\"
    echo "    --host 0.0.0.0 --port 8000"
    echo ""
else
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "❌ BUILD FAILED"
    echo "═══════════════════════════════════════════════════════════════"
    exit 1
fi