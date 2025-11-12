#!/bin/bash
# Build script for NIXL-aligned container
# Combines official ai-dynamo/nixl 0.7.1 with AWS EFA support

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Building NIXL-Aligned Container${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Configuration
DOCKER_REGISTRY="${DOCKER_REGISTRY:-058264135704.dkr.ecr.us-east-2.amazonaws.com}"
IMAGE_NAME="${IMAGE_NAME:-nixl-aligned}"
TAG="${TAG:-0.7.1}"
FULL_IMAGE="${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"

# Build arguments
NPROC="${NPROC:-12}"
INSTALL_NCCL="${INSTALL_NCCL:-0}"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Image:        ${FULL_IMAGE}"
echo "  Parallel jobs: ${NPROC}"
echo "  Install NCCL:  ${INSTALL_NCCL}"
echo "  Base:          nvcr.io/nvidia/cuda-dl-base:25.06-cuda12.9-devel-ubuntu24.04"
echo ""

# Key versions
echo -e "${YELLOW}Versions (aligned with ai-dynamo/nixl):${NC}"
echo "  NIXL:         0.7.1"
echo "  UCX:          v1.19.0"
echo "  libfabric:    v1.21.0 → /usr/local"
echo "  CUDA:         12.9"
echo "  Python:       3.12"
echo "  Ubuntu:       24.04"
echo ""

# Confirm
read -p "$(echo -e ${YELLOW}Proceed with build? [y/N]:${NC} )" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Build cancelled"
    exit 1
fi

# Build
echo ""
echo -e "${GREEN}Starting Docker build...${NC}"
echo ""

DOCKER_BUILDKIT=1 docker build \
    --progress=plain \
    --build-arg NPROC=${NPROC} \
    --build-arg INSTALL_NCCL=${INSTALL_NCCL} \
    -t ${IMAGE_NAME}:${TAG} \
    -t ${IMAGE_NAME}:latest \
    -f Dockerfile.nixl-aligned \
    . 2>&1 | tee build-nixl-aligned.log

# Check if build succeeded
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ Build successful!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Local tags:"
    echo "  ${IMAGE_NAME}:${TAG}"
    echo "  ${IMAGE_NAME}:latest"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo ""
    echo "1. Validate the image:"
    echo "   docker run --rm ${IMAGE_NAME}:${TAG} validate-nixl"
    echo ""
    echo "2. Test Python import:"
    echo "   docker run --rm ${IMAGE_NAME}:${TAG} python -c \"import nixl; print(nixl.__version__)\""
    echo ""
    echo "3. Check libfabric linkage:"
    echo "   docker run --rm ${IMAGE_NAME}:${TAG} ldd /usr/local/nixl/lib/x86_64-linux-gnu/plugins/libnixl_libfabric.so | grep libfabric"
    echo ""
    echo "4. Tag and push to ECR:"
    echo "   docker tag ${IMAGE_NAME}:${TAG} ${FULL_IMAGE}"
    echo "   aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin ${DOCKER_REGISTRY}"
    echo "   docker push ${FULL_IMAGE}"
    echo ""
else
    echo ""
    echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}❌ Build failed!${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Check build-nixl-aligned.log for details"
    exit 1
fi
