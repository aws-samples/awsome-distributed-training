# NVIDIA Dynamo + NIXL Container Suite for AWS

Production-ready containers for high-performance distributed ML workloads on AWS with EFA support, optimized for H100, A100, and A10G GPU instances.

## Overview

This container suite provides optimized Docker images for AWS GPU instances featuring:

- **Multi-GPU Architecture Support**: H100 (p5.\*), A100 (p4d.\*), A10G (g5.\*)
- **AWS EFA Networking**: Custom-built UCX and libfabric for AWS Elastic Fabric Adapter
- **vLLM Integration**: Fast pip-based installation (10-15 min build time)
- **TensorRT-LLM Support**: Optimized inference engine
- **NIXL Framework**: Network Infrastructure for eXascale Learning
- **Container Optimization**: Slim builds reduce size by 32% (17GB vs 25GB)

## Quick Start

### Build All Containers (Recommended)

For H100 instances with 16+ CPU cores:

```bash
# Production-optimized slim builds (~17GB each)
./build-all-slim.sh

# Standard runtime builds (~25GB each)
./build-all-runtime.sh
```

This builds all three containers:
1. Production Base (nixl-h100-efa:production) - NIXL + EFA foundation
2. Dynamo + vLLM - High-performance LLM serving
3. Dynamo + TensorRT-LLM - Optimized inference engine

**Build Time**: ~60-90 minutes on H100 with 16 cores

### Individual Container Builds

#### 1. Production Base (NIXL + EFA)

```bash
# H100 (default)
./build.sh

# A100
CUDA_ARCH=80 CUDA_ARCH_NAME=A100 ./build.sh

# A10G
CUDA_ARCH=86 CUDA_ARCH_NAME=A10G ./build.sh
```

#### 2. Dynamo + vLLM

```bash
# H100 slim (recommended for production)
BUILD_TARGET=slim CUDA_ARCH=90 ./build_vllm.sh

# A100 runtime
CUDA_ARCH=80 CUDA_ARCH_NAME=A100 ./build_vllm.sh

# A10G slim
BUILD_TARGET=slim CUDA_ARCH=86 CUDA_ARCH_NAME=A10G ./build_vllm.sh
```

#### 3. Dynamo + TensorRT-LLM

```bash
# H100 slim (recommended for production)
BUILD_TARGET=slim CUDA_ARCH=90 ./build_trtllm.sh

# A100 runtime
CUDA_ARCH=80 CUDA_ARCH_NAME=A100 ./build_trtllm.sh

# A10G slim
BUILD_TARGET=slim CUDA_ARCH=86 CUDA_ARCH_NAME=A10G ./build_trtllm.sh
```

## Architecture Support

| GPU  | CUDA Arch | Build Flag | AWS Instance | Default |
|------|-----------|------------|--------------|---------|
| H100 | 90 (SM90) | `CUDA_ARCH=90 CUDA_ARCH_NAME=H100` | p5.* | ✅ Yes |
| A100 | 80 (SM80) | `CUDA_ARCH=80 CUDA_ARCH_NAME=A100` | p4d.* | |
| A10G | 86 (SM86) | `CUDA_ARCH=86 CUDA_ARCH_NAME=A10G` | g5.* | |

## Container Options

### Build Targets

| Target | Size | Use Case | Build Flag |
|--------|------|----------|------------|
| **slim** | ~17GB | Production deployments | `BUILD_TARGET=slim` |
| **runtime** | ~25GB | Development, debugging | `BUILD_TARGET=runtime` (default) |
| **dev** | ~27GB | Active development | `BUILD_TARGET=dev` |

**Slim builds remove** (safely):
- Build artifacts and tools (cmake, ninja, etc.)
- Documentation and man pages
- Static libraries (shared libraries preserved)
- Python cache and temporary files

**Slim builds keep**:
- All custom libraries (UCX, EFA, NIXL, NCCL)
- Essential tools (nano, vim, curl, wget, htop, sed, grep)
- Full runtime functionality

See [DEBLOAT_GUIDE.md](DEBLOAT_GUIDE.md) for detailed optimization information.

### vLLM Installation Methods

**Pip Install (Default - Fast)**:
```bash
./build_vllm.sh  # 10-15 minutes
```
- Uses pre-built vLLM wheel
- Works with all custom libraries (UCX, EFA, NIXL)
- Recommended for production

**Source Build (Optional - Slow)**:
```bash
USE_SOURCE_BUILD=true MAX_JOBS=8 ./build_vllm.sh  # 60-90 minutes
```
- Build vLLM from source
- Useful for custom modifications
- Requires more memory (64GB+ recommended)

## Build Configuration

### All Environment Variables

#### Production Base (build.sh)
```bash
CUDA_ARCH=90              # GPU architecture (90=H100, 80=A100, 86=A10G)
CUDA_ARCH_NAME=H100       # GPU name for environment variables
INSTALL_NCCL=1            # Install NCCL (1=yes, 0=no)
INSTALL_NVSHMEM=0         # Install NVSHMEM (1=yes, 0=no)
NPROC=12                  # Parallel build jobs (12 recommended for 16-core)
TAG=production            # Docker tag
```

#### vLLM Container (build_vllm.sh)
```bash
CUDA_ARCH=90              # GPU architecture
CUDA_ARCH_NAME=H100       # GPU name
BUILD_TARGET=runtime      # Container target (runtime/slim/dev)
USE_SOURCE_BUILD=false    # Set to "true" to build vLLM from source
MAX_JOBS=12               # Parallel jobs (for source builds only)
TAG=dynamo-vllm:latest    # Docker tag
```

#### TensorRT-LLM Container (build_trtllm.sh)
```bash
CUDA_ARCH=90              # GPU architecture
CUDA_ARCH_NAME=H100       # GPU name
BUILD_TARGET=runtime      # Container target (runtime/slim/dev)
TAG=dynamo-trtllm:latest  # Docker tag
```

### Performance Settings for H100 (16 cores)

| Setting | Recommended Value | Notes |
|---------|------------------|-------|
| **NPROC** | 12 | For base container builds |
| **MAX_JOBS** | 12 | For vLLM source builds |
| **CUDA_ARCH** | 90 | H100 SM architecture |

**Why 12 instead of 16?**
- Leaves 4 cores for system overhead
- Prevents out-of-memory issues during compilation
- More stable builds

## Running Containers

### Basic Usage

```bash
# Run vLLM container
docker run -it --rm --gpus all dynamo-vllm:slim

# Run TensorRT-LLM container
docker run -it --rm --gpus all dynamo-trtllm:slim
```

### vLLM Server

```bash
# Start vLLM server
docker run -it --gpus all -p 8000:8000 dynamo-vllm:slim \
  vllm serve meta-llama/Llama-2-7b-hf \
  --host 0.0.0.0 --port 8000

# Test the server
curl http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama/Llama-2-7b-hf",
    "prompt": "San Francisco is",
    "max_tokens": 50
  }'
```

### With EFA Support

For EFA-enabled AWS instances (p5.\*, p4d.\*):

```bash
# Full EFA setup with networking
docker run --gpus all --net=host --privileged \
  -v /dev/infiniband:/dev/infiniband \
  -it dynamo-vllm:slim

# With ETCD coordination
docker run -it --rm --gpus all \
  -e NIXL_ETCD_ENDPOINTS=http://etcd-service:2379 \
  dynamo-vllm:slim
```

## AWS Deployment

### EKS (Elastic Kubernetes Service)

1. **Build and push containers to ECR**:
```bash
# Tag for ECR
docker tag dynamo-vllm:slim <account-id>.dkr.ecr.<region>.amazonaws.com/dynamo-vllm:slim

# Login to ECR
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <account-id>.dkr.ecr.<region>.amazonaws.com

# Push
docker push <account-id>.dkr.ecr.<region>.amazonaws.com/dynamo-vllm:slim
```

2. **Deploy to EKS**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: vllm-server
spec:
  containers:
  - name: vllm
    image: <account-id>.dkr.ecr.<region>.amazonaws.com/dynamo-vllm:slim
    resources:
      limits:
        nvidia.com/gpu: 1
    command: ["vllm", "serve", "meta-llama/Llama-2-7b-hf", "--host", "0.0.0.0"]
```

### HyperPod

These containers are optimized for AWS HyperPod clusters with EFA support. The NIXL networking stack integrates with HyperPod's cluster networking automatically.

### EFA Requirements

For EFA-enabled instances:
- Mount EFA devices: `-v /dev/infiniband:/dev/infiniband`
- Use host networking: `--net=host`
- Privileged mode (for RDMA): `--privileged`

## Installed Components

### Core Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| **Base Image** | NVIDIA CUDA DL Base 25.01 | CUDA 12.8, Ubuntu 24.04 |
| **CUDA** | 12.8 | GPU compute platform |
| **NCCL** | v2.27.5-1 | Collective communications |
| **UCX** | 1.19.0 | Unified communications with EFA |
| **libfabric** | 2.3.0 | Fabric library with EFA provider |
| **GDRCopy** | v2.4.4 | GPU-direct RDMA |

### Networking

| Component | Version | Purpose |
|-----------|---------|---------|
| **EFA Installer** | 1.42.0 | AWS EFA support |
| **AWS OFI NCCL Plugin** | v1.16.0 | EFA integration for NCCL |
| **NVSHMEM** | 3.2.5-1 | NVIDIA symmetric memory (optional) |
| **PMIx** | 4.2.6 | Process management |

### NIXL Framework

| Component | Version | Purpose |
|-----------|---------|---------|
| **NIXL** | 0.4.1 | Network infrastructure library |
| **nixlbench** | Latest | Benchmarking tools |
| **ETCD** | v3.5.1 | Distributed coordination |
| **AWS SDK C++** | 1.11.581 | AWS service integration |

### ML Frameworks

| Component | Container | Installation |
|-----------|-----------|--------------|
| **vLLM** | dynamo-vllm | Pip install (default) or source build |
| **TensorRT-LLM** | dynamo-trtllm | Pip install (v0.17.0) |
| **PyTorch** | All | CUDA 12.8 variant |

## Environment Variables

### CUDA Configuration
```bash
CUDAARCHS=90                        # Set by build (90/80/86)
CUDA_ARCH_NAME=H100                 # Set by build (H100/A100/A10G)
CMAKE_CUDA_ARCHITECTURES=90         # For CMake builds
TORCH_CUDA_ARCH_LIST=9.0+PTX        # For PyTorch (9.0/8.0/8.6)
CUDA_HOME=/usr/local/cuda
```

### NIXL Configuration
```bash
NIXL_PREFIX=/usr/local/nixl
NIXL_PLUGIN_DIR=/usr/local/nixl/lib/x86_64-linux-gnu/plugins
NIXL_ETCD_NAMESPACE=/nixl/agents
NIXL_ETCD_ENDPOINTS=http://etcd-service:2379  # Optional
```

### Network Configuration
```bash
FI_PROVIDER=efa
NCCL_DEBUG=INFO
NCCL_SOCKET_IFNAME=^docker,lo,veth
NVSHMEM_REMOTE_TRANSPORT=libfabric
NVSHMEM_LIBFABRIC_PROVIDER=efa
```

## Validation & Testing

### Built-in Tools

```bash
# Environment information
env-info

# EFA connectivity tests (requires EFA hardware)
efa-test

# NIXL performance benchmarks
nixlbench-test

# Container debloating (for custom optimization)
debloat-container.sh
```

### Manual Testing

```bash
# Test vLLM installation
python3 -c "import vllm; print(vllm.__version__)"

# Test EFA detection
fi_info -p efa

# Test NCCL with EFA
all_reduce_perf -b 8 -e 128M -f 2 -g 1

# Test NIXL Python bindings
python3 -c "import nixl; print(dir(nixl))"
```

## Build Time & Size Estimates

### H100 with 16 cores, pip install (recommended)

| Container | Slim Build | Runtime Build |
|-----------|------------|---------------|
| **Base** | ~30 min, 24GB | ~30 min, 24GB |
| **vLLM** | ~12 min, 17GB | ~12 min, 25GB |
| **TensorRT-LLM** | ~18 min, 17GB | ~18 min, 25GB |
| **Total** | ~60 min | ~60 min |

### With vLLM source build (optional, slower)

| Container | Build Time | Notes |
|-----------|------------|-------|
| **vLLM (source)** | +60-90 min | Adds significant time, requires 64GB+ RAM |

### Memory Requirements

| Build Type | Recommended RAM |
|-----------|----------------|
| **Slim builds** | 64GB+ |
| **Runtime builds** | 64GB+ |
| **Source builds** | 128GB+ |

## Troubleshooting

### EFA Issues

```bash
# Check EFA hardware
fi_info -p efa

# Verify EFA driver
cat /sys/class/infiniband/*/device/vendor

# Check device mounting
ls -la /dev/infiniband/

# Ensure container has EFA access
docker run --rm --privileged -v /dev/infiniband:/dev/infiniband \
  dynamo-vllm:slim fi_info -p efa
```

### NCCL Communication Failures

```bash
# Run NCCL tests
all_reduce_perf -b 8 -e 128M -f 2 -g 1

# Enable debug output
export NCCL_DEBUG=INFO

# Check EFA plugin
ls -la /usr/local/lib/libnccl-net.so
```

### Build Failures

**Out of Memory**:
```bash
# Reduce parallel jobs
MAX_JOBS=8 ./build_vllm.sh

# Or for base builds
NPROC=8 ./build.sh
```

**Container Too Large**:
```bash
# Use slim target
BUILD_TARGET=slim ./build_vllm.sh  # Saves 8GB
```

**Slow vLLM Build**:
```bash
# Ensure using pip install (default)
./build_vllm.sh  # Should be fast (10-15 min)

# If accidentally using source build:
USE_SOURCE_BUILD=false ./build_vllm.sh
```

### GPU Not Accessible

```bash
# Check GPU
nvidia-smi

# Test Docker GPU support
docker run --rm --gpus all nvidia/cuda:12.8-runtime-ubuntu24.04 nvidia-smi

# Ensure NVIDIA Container Toolkit is installed
dpkg -l | grep nvidia-container-toolkit
```

## Advanced Usage

### Custom Docker Build

```bash
# Direct docker build for A100 slim vLLM
docker build \
  --build-arg CUDA_ARCH=80 \
  --build-arg CUDA_ARCH_NAME=A100 \
  --target slim \
  -f Dockerfile.dynamo-vllm \
  -t dynamo-vllm:a100-slim \
  .
```

### Custom Tags

```bash
# Build with custom tag
BUILD_TARGET=slim TAG=vllm:prod-v1 ./build_vllm.sh
```

### Multi-Architecture Builds

```bash
# Build all architectures
for arch in "80:A100" "86:A10G" "90:H100"; do
  IFS=':' read -r cuda_arch name <<< "$arch"
  BUILD_TARGET=slim \
    CUDA_ARCH=$cuda_arch \
    CUDA_ARCH_NAME=$name \
    TAG=dynamo-vllm:$name-slim \
    ./build_vllm.sh
done
```

## Container Specifications

**Expected Sizes**:
- Base: ~24GB
- vLLM slim: ~17GB
- vLLM runtime: ~25GB
- TensorRT-LLM slim: ~17GB
- TensorRT-LLM runtime: ~25GB

**Build Requirements**:
- Memory: 64GB+ (128GB for source builds)
- Storage: 100GB+ free space
- Build Time: 60-90 minutes for all containers

**Runtime Requirements**:
- GPU: NVIDIA H100/A100/A10G with CUDA Compute 8.0+
- Network: EFA-enabled instance for full functionality (p5.\*, p4d.\*)
- Memory: 16GB+ system RAM
- Docker: 20.10+ with NVIDIA Container Toolkit

## Repository Structure

```
dynamo-workshop/
├── Dockerfile.production              # Base NIXL+EFA container
├── Dockerfile.dynamo-vllm            # vLLM container
├── Dockerfile.dynamo-trtllm          # TensorRT-LLM container
├── build.sh                          # Build production base
├── build_vllm.sh                     # Build vLLM container
├── build_trtllm.sh                   # Build TensorRT-LLM container
├── build-all-slim.sh                 # Build all (optimized)
├── build-all-runtime.sh              # Build all (standard)
├── README.md                         # This file
├── DEBLOAT_GUIDE.md                  # Size optimization guide
├── LICENSE                           # Apache 2.0
├── ATTRIBUTION.md                    # Credits
├── nvidia_entrypoint.sh              # Container entrypoint
├── benchmarks/                       # Performance benchmarks
├── container/                        # Container dependencies
│   ├── deps/                         # Python requirements
│   └── nvidia_entrypoint.sh          # Entrypoint script
├── pkg-config-files/                 # Build dependencies
│   ├── efa.pc                        # EFA pkg-config
│   └── gdrcopy.pc                    # GDRCopy pkg-config
└── scripts/                          # Utility scripts
    ├── debloat-container.sh          # Size optimization
    ├── efa-test.sh                   # EFA testing
    ├── env-info.sh                   # Environment info
    └── nixlbench-test.sh             # Benchmarking
```

## Authors

**Built for Amazon Web Services by:**
- Anton Alexander
- Alex Iankoulski

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details.

## Credits

See [ATTRIBUTION.md](ATTRIBUTION.md) for acknowledgments of open-source components.

## Support

For issues, questions, or contributions:
- **Issues**: [GitHub Issues](https://github.com/dmvevents/dynamo-workshop/issues)
- **Documentation**: This README and [DEBLOAT_GUIDE.md](DEBLOAT_GUIDE.md)
- **AWS Support**: Contact AWS for EFA and GPU instance support

---

**Built for AWS | Optimized for H100/A100/A10G | Production-Ready**
