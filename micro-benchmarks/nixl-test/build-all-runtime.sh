#!/bin/bash
# build-all-runtime.sh - Build all containers in runtime mode (standard, no debloating)
# Optimized for H100 with 16 cores

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration for H100
CUDA_ARCH="${CUDA_ARCH:-90}"
CUDA_ARCH_NAME="${CUDA_ARCH_NAME:-H100}"
MAX_JOBS="${MAX_JOBS:-12}"  # 12 jobs for 16-core system (leave headroom)
BUILD_TARGET="runtime"

echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Building All Containers in RUNTIME Mode (Standard)${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  GPU:             ${CUDA_ARCH_NAME} (SM${CUDA_ARCH})"
echo "  Build Target:    ${BUILD_TARGET} (standard, not debloated)"
echo "  Max Jobs:        ${MAX_JOBS}"
echo "  Expected Size:   ~25GB per container"
echo ""
echo -e "${GREEN}Containers to build:${NC}"
echo "  1. Production Base (nixl-h100-efa:production)"
echo "  2. Dynamo + vLLM (dynamo-vllm:latest)"
echo "  3. Dynamo + TensorRT-LLM (dynamo-trtllm:latest)"
echo ""
echo -e "${YELLOW}Note: Total build time ~90-120 minutes on H100 with 16 cores${NC}"
echo ""

# Confirmation
read -p "Proceed with runtime builds? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Build cancelled"
    exit 0
fi

START_TIME=$(date +%s)

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 1/3: Building Production Base Container${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Build production base
CUDA_ARCH=$CUDA_ARCH \
CUDA_ARCH_NAME=$CUDA_ARCH_NAME \
NPROC=$MAX_JOBS \
TAG=production \
./build.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Production base build failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Production base completed${NC}"
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 2/3: Building Dynamo + vLLM (Runtime)${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Build vLLM runtime
BUILD_TARGET=$BUILD_TARGET \
CUDA_ARCH=$CUDA_ARCH \
CUDA_ARCH_NAME=$CUDA_ARCH_NAME \
MAX_JOBS=$MAX_JOBS \
TAG=dynamo-vllm:latest \
./build_vllm.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ vLLM build failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ vLLM runtime completed${NC}"
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 3/3: Building Dynamo + TensorRT-LLM (Runtime)${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Build TensorRT-LLM runtime
BUILD_TARGET=$BUILD_TARGET \
CUDA_ARCH=$CUDA_ARCH \
CUDA_ARCH_NAME=$CUDA_ARCH_NAME \
TAG=dynamo-trtllm:latest \
./build_trtllm.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ TensorRT-LLM build failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ TensorRT-LLM runtime completed${NC}"
echo ""

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ ALL BUILDS COMPLETED SUCCESSFULLY${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Built containers:${NC}"
echo "  1. nixl-h100-efa:production       (base)"
echo "  2. dynamo-vllm:latest             (~25GB)"
echo "  3. dynamo-trtllm:latest           (~25GB)"
echo ""
echo "Total build time: ${MINUTES}m ${SECONDS}s"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  # Run vLLM server"
echo "  docker run -it --gpus all -p 8000:8000 dynamo-vllm:latest \\"
echo "    vllm serve meta-llama/Llama-2-7b-hf --host 0.0.0.0 --port 8000"
echo ""
echo "  # View container sizes"
echo "  docker images | grep -E 'dynamo|nixl'"
echo ""
echo -e "${YELLOW}Note: To build smaller containers, use ./build-all-slim.sh instead${NC}"
echo ""
