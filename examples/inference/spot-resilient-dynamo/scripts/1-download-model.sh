#!/bin/bash
# 1-download-model.sh — Model download (placeholder)
#
# Qwen2.5-3B-Instruct is a public model (~6 GB). The vLLM worker downloads
# it automatically from HuggingFace on first startup. No manual download or
# shared filesystem is needed for this small model.
#
# This script exists for consistency with the awsome-distributed-ai convention.
# For larger models or repeated restarts, consider caching weights on an EBS
# PVC or FSx for Lustre volume.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/../env_vars"

echo "Model: $MODEL_ID"
echo "Size: ~6 GB (BF16)"
echo "License: Apache 2.0"
echo ""
echo "No manual download needed — vLLM downloads on startup."
echo "To pre-cache, mount a PVC at /models and set --model /models/Qwen2.5-3B-Instruct"
