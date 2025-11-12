#!/bin/bash
# vLLM installation script for Dynamo
# Based on NVIDIA's official installation approach

set -e

# Default values
VLLM_REF="v0.10.2"
MAX_JOBS=16
ARCH="amd64"
INSTALLATION_DIR="/opt"
TORCH_BACKEND="cu128"
CUDA_VERSION="12.8"
EDITABLE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vllm-ref) VLLM_REF="$2"; shift 2 ;;
        --max-jobs) MAX_JOBS="$2"; shift 2 ;;
        --arch) ARCH="$2"; shift 2 ;;
        --installation-dir) INSTALLATION_DIR="$2"; shift 2 ;;
        --deepgemm-ref) DEEPGEMM_REF="$2"; shift 2 ;;
        --flashinf-ref) FLASHINF_REF="$2"; shift 2 ;;
        --torch-backend) TORCH_BACKEND="$2"; shift 2 ;;
        --cuda-version) CUDA_VERSION="$2"; shift 2 ;;
        --editable) EDITABLE="--editable"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "=== Installing vLLM ==="
echo "  Version: $VLLM_REF"
echo "  Max jobs: $MAX_JOBS"
echo "  Architecture: $ARCH"
echo "  Install dir: $INSTALLATION_DIR"
echo "  Flash Attention: ${FLASHINF_REF:-default}"
echo "  DeepGEMM: ${DEEPGEMM_REF:-disabled}"
echo "  Torch backend: $TORCH_BACKEND"
echo "  CUDA version: $CUDA_VERSION"
echo "  Editable: ${EDITABLE:-no}"
echo ""

# Clone vLLM
cd /tmp
if [ ! -d "vllm" ]; then
    git clone https://github.com/vllm-project/vllm.git
fi
cd vllm
git checkout $VLLM_REF

# Fix pyproject.toml for newer setuptools compatibility
echo "=== Patching pyproject.toml for setuptools compatibility ==="
if [ -f "pyproject.toml" ]; then
    # Replace license = "Apache-2.0" with license = {text = "Apache-2.0"}
    sed -i 's/^license = "Apache-2.0"$/license = {text = "Apache-2.0"}/' pyproject.toml
    
    # Remove license-files from [project] section (it belongs in [tool.setuptools])
    sed -i '/^license-files = /d' pyproject.toml
    
    echo "✓ Patched pyproject.toml"
fi

echo "=== Installing PyTorch ==="
# Install PyTorch first
uv pip install --index-url https://download.pytorch.org/whl/${TORCH_BACKEND} \
    torch torchvision

echo "=== Installing build dependencies ==="
# Install ALL build dependencies that vLLM needs
uv pip install \
    packaging \
    wheel \
    setuptools \
    setuptools-scm \
    ninja \
    cmake \
    pybind11 \
    Cython

echo "=== Installing vLLM dependencies ==="
# Install vLLM dependencies based on what files exist in the repo
if [ -f "requirements-common.txt" ]; then
    echo "Installing from requirements-common.txt"
    uv pip install -r requirements-common.txt
fi

if [ -f "requirements-cuda.txt" ]; then
    echo "Installing from requirements-cuda.txt"
    uv pip install -r requirements-cuda.txt
fi

# Fallback to requirements.txt if the above don't exist
if [ ! -f "requirements-common.txt" ] && [ -f "requirements.txt" ]; then
    echo "Using requirements.txt instead of requirements-common.txt"
    uv pip install -r requirements.txt
fi

# Install build dependencies if available
if [ -f "requirements-build.txt" ]; then
    echo "Installing from requirements-build.txt"
    uv pip install -r requirements-build.txt
fi

echo "=== Building and installing vLLM ==="
# Set build environment with FULL parallelism support
export MAX_JOBS=$MAX_JOBS
export CUDA_HOME=/usr/local/cuda
export NVCC_THREADS=$MAX_JOBS

# CRITICAL: Set parallelism for ALL build systems
export CMAKE_BUILD_PARALLEL_LEVEL=$MAX_JOBS
export MAKEFLAGS="-j${MAX_JOBS}"
export NINJA_FLAGS="-j${MAX_JOBS}"

# Set architecture-specific compilation flags
if [ "$ARCH" = "arm64" ]; then
    export TORCH_CUDA_ARCH_LIST="9.0+PTX"  # H100/H200
else
    export TORCH_CUDA_ARCH_LIST="9.0"  # H100
fi

echo "🔧 Build configuration:"
echo "   MAX_JOBS: $MAX_JOBS"
echo "   CMAKE_BUILD_PARALLEL_LEVEL: $CMAKE_BUILD_PARALLEL_LEVEL"
echo "   TORCH_CUDA_ARCH_LIST: $TORCH_CUDA_ARCH_LIST"
echo ""

# Build and install vLLM
if [ -n "$EDITABLE" ]; then
    echo "Installing vLLM in editable mode..."
    uv pip install --no-build-isolation -e .
else
    echo "Installing vLLM..."
    uv pip install --no-build-isolation .
fi

# Copy installation to desired location
echo "=== Copying vLLM to $INSTALLATION_DIR/vllm ==="
mkdir -p $INSTALLATION_DIR/vllm
cp -r /tmp/vllm/* $INSTALLATION_DIR/vllm/

# Install FlashInfer if specified
if [ -n "$FLASHINF_REF" ]; then
    echo "=== Installing FlashInfer ${FLASHINF_REF} ==="
    cd /tmp
    if [ ! -d "flashinfer" ]; then
        git clone https://github.com/flashinfer-ai/flashinfer.git
    fi
    cd flashinfer
    git checkout $FLASHINF_REF
    uv pip install --no-build-isolation -e .
fi

# Install DeepGEMM if specified
if [ -n "$DEEPGEMM_REF" ]; then
    echo "=== Installing DeepGEMM ${DEEPGEMM_REF} ==="
    cd /tmp
    if [ ! -d "deepgemm" ]; then
        git clone https://github.com/deepgemm/deepgemm.git
    fi
    cd deepgemm
    git checkout $DEEPGEMM_REF
    uv pip install --no-build-isolation -e .
fi

echo ""
echo "✅ vLLM installation complete"
echo ""
echo "Installed packages:"
uv pip list | grep -E "vllm|torch|flash|deepgemm" || true
