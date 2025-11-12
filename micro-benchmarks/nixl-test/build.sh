#!/bin/bash
# build.sh - Production container build script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
IMAGE_NAME="nixl-h100-efa"
TAG="${TAG:-production}"
DOCKERFILE="${DOCKERFILE:-Dockerfile.production}"

# Architecture options
CUDA_ARCH="${CUDA_ARCH:-90}"
CUDA_ARCH_NAME="${CUDA_ARCH_NAME:-H100}"

# Build options
INSTALL_NCCL="${INSTALL_NCCL:-1}"
INSTALL_NVSHMEM="${INSTALL_NVSHMEM:-0}"
NPROC="${NPROC:-$(nproc)}"

echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Building ${IMAGE_NAME}:${TAG}${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Dockerfile:      ${DOCKERFILE}"
echo "  Tag:             ${IMAGE_NAME}:${TAG}"
echo "  GPU Arch:        SM${CUDA_ARCH} (${CUDA_ARCH_NAME})"
echo "  Install NCCL:    ${INSTALL_NCCL}"
echo "  Install NVSHMEM: ${INSTALL_NVSHMEM}"
echo "  Parallel jobs:   ${NPROC}"
echo ""

# Confirmation
read -p "Proceed with build? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Build cancelled"
    exit 0
fi

# Build with BuildKit optimizations
echo -e "${BLUE}Starting build...${NC}"
export DOCKER_BUILDKIT=1
docker build \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --build-arg CUDA_ARCH=${CUDA_ARCH} \
    --build-arg CUDA_ARCH_NAME=${CUDA_ARCH_NAME} \
    --build-arg INSTALL_NCCL=${INSTALL_NCCL} \
    --build-arg INSTALL_NVSHMEM=${INSTALL_NVSHMEM} \
    --build-arg NPROC=${NPROC} \
    -f ${DOCKERFILE} \
    -t ${IMAGE_NAME}:${TAG} \
    .

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ BUILD SUCCESSFUL${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Image: ${IMAGE_NAME}:${TAG}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  1. Check build: docker run --rm ${IMAGE_NAME}:${TAG} validate-build"
echo "  2. View info:   docker run --rm ${IMAGE_NAME}:${TAG} env-info"
echo "  3. Run shell:   docker run -it --gpus all ${IMAGE_NAME}:${TAG}"
echo ""