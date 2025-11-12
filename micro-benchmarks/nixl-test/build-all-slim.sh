#!/bin/bash
# build-all-slim.sh - Build all containers in slim (debloated) mode
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
MAX_JOBS="${MAX_JOBS:-24}"  # 12 jobs for 16-core system (leave headroom)
BUILD_TARGET="slim"

echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Building All Containers in SLIM Mode (Production Optimized)${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  GPU:             ${CUDA_ARCH_NAME} (SM${CUDA_ARCH})"
echo "  Build Target:    ${BUILD_TARGET} (debloated)"
echo "  Max Jobs:        ${MAX_JOBS}"
echo "  Expected Size:   ~17GB per container (vs 25GB standard)"
echo ""
echo -e "${GREEN}Containers to build:${NC}"
echo "  1. Production Base (nixl-h100-efa:production)"
echo "  2. Dynamo + vLLM (dynamo-vllm:slim)"
echo "  3. Dynamo + TensorRT-LLM (dynamo-trtllm:slim)"
echo ""
echo -e "${YELLOW}Note: Total build time ~90-120 minutes on H100 with 16 cores${NC}"
echo ""

# Confirmation
read -p "Proceed with slim builds? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Build cancelled"
    exit 0
fi

START_TIME=$(date +%s)

# Enable BuildKit for optimizations
export DOCKER_BUILDKIT=1

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 1/3: Building Production Base Container${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Build production base (this doesn't have a slim target, but it's already optimized)
docker build \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --build-arg CUDA_ARCH=$CUDA_ARCH \
    --build-arg CUDA_ARCH_NAME=$CUDA_ARCH_NAME \
    --build-arg INSTALL_NCCL=1 \
    --build-arg INSTALL_NVSHMEM=0 \
    --build-arg NPROC=$MAX_JOBS \
    -f Dockerfile.production \
    -t nixl-h100-efa:production \
    .

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Production base build failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Production base completed${NC}"
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 2/3: Building Dynamo + vLLM (Slim)${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Build vLLM slim
NIXL_BASE_IMAGE=nixl-h100-efa:production \
BUILD_TARGET=$BUILD_TARGET \
CUDA_ARCH=$CUDA_ARCH \
CUDA_ARCH_NAME=$CUDA_ARCH_NAME \
MAX_JOBS=$MAX_JOBS \
TAG=dynamo-vllm:slim \
./build_vllm.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ vLLM build failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ vLLM slim completed${NC}"
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 3/3: Building Dynamo + TensorRT-LLM (Slim)${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Build TensorRT-LLM slim
NIXL_BASE_IMAGE=nixl-h100-efa:production \
BUILD_TARGET=$BUILD_TARGET \
CUDA_ARCH=$CUDA_ARCH \
CUDA_ARCH_NAME=$CUDA_ARCH_NAME \
TAG=dynamo-trtllm:slim \
./build_trtllm.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ TensorRT-LLM build failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ TensorRT-LLM slim completed${NC}"
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
echo "  2. dynamo-vllm:slim               (~17GB)"
echo "  3. dynamo-trtllm:slim             (~17GB)"
echo ""
echo "Total build time: ${MINUTES}m ${SECONDS}s"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  # Run vLLM server"
echo "  docker run -it --gpus all -p 8000:8000 dynamo-vllm:slim \\"
echo "    vllm serve meta-llama/Llama-2-7b-hf --host 0.0.0.0 --port 8000"
echo ""
echo "  # View container sizes"
echo "  docker images | grep -E 'dynamo|nixl'"
echo ""
