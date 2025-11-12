# Container Debloating Guide

Reduce your container sizes by 30-50% while keeping all essential functionality.

## Quick Start

### Build Slim Containers (Recommended for Production)

```bash
# vLLM - Slim version
BUILD_TARGET=slim TAG=dynamo-vllm:slim ./build_vllm.sh

# TensorRT-LLM - Slim version
BUILD_TARGET=slim TAG=dynamo-trtllm:slim ./build_trtllm.sh
```

### Build Options

| Target | Size | Use Case | Build Command |
|--------|------|----------|---------------|
| **runtime** | ~25GB | Standard deployment | `./build_vllm.sh` |
| **slim** | ~17-18GB | Production (optimized) | `BUILD_TARGET=slim ./build_vllm.sh` |
| **dev** | ~27GB | Development (extra tools) | `BUILD_TARGET=dev ./build_vllm.sh` |

## What Gets Removed in Slim Builds?

### ❌ Removed (Safe)
- **Build artifacts**: `*.o`, `*.a`, CMake files
- **Python cache**: `__pycache__`, `*.pyc`, `*.pyo`
- **Static libraries**: All `.a` files (keeping `.so` shared libraries)
- **Build tools**: cmake, ninja-build, autoconf, automake
- **Documentation**: man pages, info pages, docs
- **Temporary files**: `/tmp/*`, `/var/tmp/*`
- **APT cache**: All package cache and lists
- **Source directories**: Git repos used for building

### ✅ Kept (Essential)
- **All runtime libraries**: UCX, EFA, libfabric, NIXL, NCCL, GDRCopy
- **CUDA runtime and tools**
- **Python packages**: vLLM, PyTorch, TensorRT-LLM
- **Editors**: nano, vim
- **Network tools**: curl, wget, ssh
- **Debug tools**: htop, strace
- **Git** (for version control)

## Manual Debloating

You can also run the debloat script manually on existing containers:

### Option 1: Inside Running Container
```bash
# Start container
docker run -it --gpus all dynamo-vllm:latest bash

# Run debloat script
/workspace/scripts/debloat-container.sh

# Exit and commit changes
exit
docker commit <container-id> dynamo-vllm:slim
```

### Option 2: From Host
```bash
# Copy script to container
docker cp scripts/debloat-container.sh <container-id>:/tmp/

# Execute inside container
docker exec <container-id> bash /tmp/debloat-container.sh

# Commit changes
docker commit <container-id> dynamo-vllm:slim
```

## Size Comparison

### Before (Standard Runtime)
```
REPOSITORY          TAG       SIZE
dynamo-vllm         latest    25.3GB
dynamo-trtllm       latest    24.8GB
```

### After (Slim Build)
```
REPOSITORY          TAG       SIZE
dynamo-vllm         slim      17.2GB  (-32%)
dynamo-trtllm       slim      16.9GB  (-32%)
```

## What's Different Between Targets?

### Runtime (Default)
```bash
./build_vllm.sh
```
- Standard deployment image
- Includes all build dependencies (for potential extensions)
- ~25GB

### Slim (Production Optimized)
```bash
BUILD_TARGET=slim ./build_vllm.sh
```
- Debloated for production
- Removed build tools and caches
- Keeps essential editors and debug tools
- ~17-18GB (30-40% smaller)

### Dev (Development)
```bash
BUILD_TARGET=dev ./build_vllm.sh
```
- All runtime tools PLUS:
  - Extra development tools (nvtop, tmux, rsync, etc.)
  - Rust toolchain
  - Maturin for Python/Rust development
- ~27GB

## Advanced: Custom Debloating

Edit `scripts/debloat-container.sh` to customize what gets removed:

```bash
# Keep more build tools
REMOVE_BUILD_TOOLS=(
    cmake
    ninja-build
    # Keep gcc/g++ by commenting out:
    # gcc
    # g++
)

# Strip debug symbols (saves more space but harder debugging)
find /usr/local -type f -executable -exec strip --strip-debug {} \; 2>/dev/null
```

## Verification After Debloating

Test that everything still works:

```bash
# Test vLLM
docker run --rm --gpus all dynamo-vllm:slim \
  python -c "import vllm; print('vLLM OK')"

# Test NIXL
docker run --rm --gpus all dynamo-vllm:slim nixl-validate

# Test networking
docker run --rm --gpus all dynamo-vllm:slim \
  bash -c "ldconfig -p | grep -E 'libfabric|libucs|libnccl'"
```

## Examples

### Build A100 Slim Container
```bash
CUDA_ARCH=80 CUDA_ARCH_NAME=A100 BUILD_TARGET=slim TAG=vllm-a100:slim ./build_vllm.sh
```

### Build H100 Dev Container
```bash
CUDA_ARCH=90 CUDA_ARCH_NAME=H100 BUILD_TARGET=dev TAG=vllm-h100:dev ./build_vllm.sh
```

### Build with Pip + Slim
```bash
# Fast pip install + debloated
BUILD_TARGET=slim TAG=vllm-slim:latest ./build_vllm.sh
```

### Build from Source + Slim
```bash
# Source build + debloated (still saves space on build artifacts)
USE_SOURCE_BUILD=true BUILD_TARGET=slim TAG=vllm-source-slim:latest ./build_vllm.sh
```

## Troubleshooting

### "Command not found" after debloating

If you need a removed tool:

```bash
# Re-install specific tools
docker exec -it <container> apt-get update
docker exec -it <container> apt-get install -y <tool-name>
```

### Need to rebuild extension at runtime

Use `runtime` or `dev` target instead of `slim` if you need to compile Python extensions:

```bash
BUILD_TARGET=runtime ./build_vllm.sh
```

### Space not reduced as expected

Check what's taking space:

```bash
docker exec <container> du -h --max-depth=1 / | sort -hr | head -20
```

## Best Practices

1. **Production**: Use `slim` target
2. **Development**: Use `dev` target
3. **CI/CD**: Use `runtime` or `slim` target
4. **Custom builds**: Start with `runtime`, add custom tools, then debloat

## FAQ

**Q: Will this break my custom libraries (UCX, EFA, NIXL)?**
A: No! All runtime libraries and binaries are preserved. Only build artifacts are removed.

**Q: Can I still edit files in the container?**
A: Yes! nano and vim are kept specifically for this purpose.

**Q: What if I need to install something later?**
A: You can still use `apt-get install` - the package manager still works.

**Q: Does this affect performance?**
A: No performance impact. Only unused files are removed.

**Q: Should I use slim for development?**
A: No, use the `dev` target which includes extra development tools.
