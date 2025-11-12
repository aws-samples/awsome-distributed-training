#!/bin/bash
# NVIDIA container entrypoint

echo ""
echo "=========="
echo "== CUDA =="
echo "=========="
echo ""

if [ -f /usr/local/cuda/version.json ]; then
    CUDA_VER=$(cat /usr/local/cuda/version.json 2>/dev/null | jq -r '.cuda.version' 2>/dev/null || echo 'unknown')
    echo "CUDA Version: $CUDA_VER"
elif command -v nvcc >/dev/null 2>&1; then
    nvcc --version | grep "release" || echo "nvcc found but version unknown"
else
    echo "WARNING: CUDA not detected"
fi
echo ""

# Check for GPU
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi -L 2>/dev/null || echo "WARNING: No NVIDIA GPU detected (use docker run --gpus all)"
else
    echo "WARNING: nvidia-smi not available"
fi
echo ""

exec "$@"
