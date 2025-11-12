#!/bin/bash
# FAST vLLM installation using pre-built wheels (like TensorRT-LLM approach)

set -e

TORCH_BACKEND="${TORCH_BACKEND:-cu128}"
VLLM_VERSION="${VLLM_VERSION:-0.11.0}"

echo "=== Installing vLLM (FAST MODE - Pre-built wheels) ==="
echo "  vLLM version: $VLLM_VERSION"
echo "  PyTorch backend: $TORCH_BACKEND"
echo ""

# Install PyTorch
echo "=== Installing PyTorch ==="
uv pip install --index-url https://download.pytorch.org/whl/${TORCH_BACKEND} \
    torch torchvision

# Install vLLM from PyPI (pre-built wheel - FAST!)
echo "=== Installing vLLM from PyPI ==="
uv pip install vllm==${VLLM_VERSION}

echo ""
echo "✅ vLLM installation complete (in ~5 minutes!)"
echo ""
echo "Installed packages:"
uv pip list | grep -E "vllm|torch" || true
