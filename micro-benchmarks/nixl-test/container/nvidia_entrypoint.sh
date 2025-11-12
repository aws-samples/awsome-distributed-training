#!/bin/bash
# NVIDIA container entrypoint

echo ""
echo "========================================="
echo "== NVIDIA Dynamo + NIXL + vLLM =="
echo "========================================="
echo ""

# Execute command
exec "$@"
