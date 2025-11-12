# Version and Approach Comparison

## ai-dynamo/nixl Official Dockerfile vs Our Production Dockerfile

**Date**: 2025-11-09
**Goal**: Align our container build with official NIXL approach

---

## Key Version Differences

| Component | Official NIXL | Our Production | Decision |
|-----------|---------------|----------------|----------|
| **NIXL Version** | 0.7.1 (latest) | 0.6.0 | ✅ **Upgrade to 0.7.1** |
| **Base Image** | cuda-dl-base:25.06-cuda12.9 | pytorch:25.06-py3 | ✅ **Use cuda-dl-base** |
| **CUDA** | 12.9 | 12.8 | ✅ **Upgrade to 12.9** |
| **Ubuntu** | 24.04 | 22.04 | ✅ **Upgrade to 24.04** |
| **Python** | 3.12 | 3.10/3.11 | ✅ **Use 3.12** |
| **UCX** | v1.19.0 | v1.19.0 (commit) | ✅ **Use v1.19.0 tag** |
| **libfabric** | v1.21.0 | v2.3.0 | ⚠️ **Use v1.21.0** (older but official) |
| **libfabric install** | /usr/local | /opt/amazon/efa | ⚠️ **Critical difference** |
| **NIXL install** | /usr/local/nixl | /opt/nvidia/nvda_nixl | ✅ **Use /usr/local/nixl** |
| **Rust** | 1.86.0 | 1.90.0 | ✅ **Use 1.86.0** |
| **EFA Installer** | Not used | v1.43.3 | ⚠️ **Add EFA installer** |

---

## Critical Differences

### 1. libfabric Installation Path

**Official NIXL**: Builds libfabric from source to `/usr/local`
```dockerfile
ARG LIBFABRIC_VERSION="v1.21.0"
ARG LIBFABRIC_INSTALL_PATH="/usr/local"

RUN wget "https://github.com/ofiwg/libfabric/releases/download/${LIBFABRIC_VERSION}/libfabric-${LIBFABRIC_VERSION#v}.tar.bz2" && \
    ./configure --prefix="${LIBFABRIC_INSTALL_PATH}" \
                --enable-efa \
                --with-cuda=/usr/local/cuda
```

**Our Production**: Uses EFA installer which puts libfabric in `/opt/amazon/efa`
```dockerfile
ARG LIBFABRIC_INSTALL_PATH="/opt/amazon/efa"
# EFA installer installs libfabric + EFA provider
```

**Impact**: Friend's issue - NIXL must be compiled with correct libfabric path

**Decision**:
- ✅ Build libfabric from source like official NIXL
- ✅ Use v1.21.0 (their version)
- ✅ Install to `/usr/local` for consistency
- ✅ BUT also install AWS EFA drivers/tools separately

### 2. NIXL Build Configuration

**Official NIXL**:
```dockerfile
ENV NIXL_PREFIX=$NIXL_PREFIX
RUN meson setup -Dlibfabric_path=$LIBFABRIC_INSTALL_PATH build/ --prefix=$NIXL_PREFIX && \
    cd build && \
    ninja && \
    ninja install
```

**Critical flag**: `-Dlibfabric_path=$LIBFABRIC_INSTALL_PATH`

This is exactly the fix your friend mentioned! They use it explicitly.

### 3. Base Image Strategy

**Official NIXL**: Uses `cuda-dl-base` (lightweight CUDA development)
```dockerfile
ARG BASE_IMAGE="nvcr.io/nvidia/cuda-dl-base"
ARG BASE_IMAGE_TAG="25.06-cuda12.9-devel-ubuntu24.04"
```

**Our Production**: Uses `pytorch` (includes full ML stack)
```dockerfile
FROM nvcr.io/nvidia/pytorch:25.06-py3
```

**Decision**: Use `cuda-dl-base` for smaller image, install PyTorch separately via pip

### 4. Python Environment

**Official NIXL**: Uses `uv` for fast package management + virtual environment
```dockerfile
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
ENV VIRTUAL_ENV=/workspace/.venv
RUN uv venv $VIRTUAL_ENV --python $DEFAULT_PYTHON_VERSION
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
```

**Our Production**: System-wide Python packages

**Decision**: ✅ Use uv + virtual environment (cleaner, faster)

### 5. DOCA Installation

**Official NIXL**: Installs DOCA packages (required for GPUNetIO backend)
```dockerfile
RUN apt-get install -y --no-install-recommends \
    doca-sdk-gpunetio libdoca-sdk-gpunetio-dev libdoca-sdk-verbs-dev
```

**Our Production**: Not installed

**Decision**: ✅ Include DOCA for GPUNetIO support

### 6. gusli Library

**Official NIXL**: Builds gusli (NVIDIA storage library)
```dockerfile
RUN git clone https://github.com/nvidia/gusli.git && \
    cd gusli && \
    make all BUILD_RELEASE=1
```

**Our Production**: Not included

**Decision**: ✅ Include gusli for storage backends

---

## Build Approach Comparison

### Official NIXL Approach

```
1. Start with cuda-dl-base
2. Install system dependencies
3. Install DOCA (GPUNetIO)
4. Build etcd-cpp-api
5. Build AWS SDK
6. Build gusli
7. Install Rust
8. Remove old UCX
9. Build UCX from source
10. Build libfabric from source (v1.21.0 to /usr/local)
11. Create Python venv with uv
12. Build NIXL with -Dlibfabric_path=/usr/local
13. Build NIXL wheel
14. Install wheel
```

### Our Production Approach

```
1. Start with pytorch base
2. Install EFA installer (includes libfabric 2.3 to /opt/amazon/efa)
3. Build libfabric separately (v2.3.0 to /opt/amazon/efa)
4. Build UCX from source
5. Build NIXL with -Dlibfabric_path=/opt/amazon/efa
6. Build GDRCopy, NCCL, etc.
```

**Key Difference**: We use AWS EFA installer, they build everything from source

---

## Recommendations for Aligned Build

### Hybrid Approach (Best of Both)

1. ✅ **Use official NIXL versions** (0.7.1, libfabric 1.21.0, etc.)
2. ✅ **Use official NIXL base image** (cuda-dl-base)
3. ✅ **Build libfabric from source** like official NIXL
4. ✅ **BUT also install AWS EFA drivers** for kernel modules
5. ✅ **Use uv + virtual environment** for Python
6. ✅ **Include DOCA** for GPUNetIO
7. ✅ **Include gusli** for storage backends
8. ✅ **Keep our NCCL/GDRCopy** builds (not in official NIXL)

### Dockerfile Structure

```dockerfile
# Stage 1: Base with dependencies
FROM nvcr.io/nvidia/cuda-dl-base:25.06-cuda12.9-devel-ubuntu24.04
# Install system packages + DOCA

# Stage 2: AWS EFA (drivers only, not libfabric)
# Install EFA kernel drivers (but skip libfabric)

# Stage 3: Build networking stack
# Build libfabric v1.21.0 from source to /usr/local
# Build UCX v1.19.0
# Build GDRCopy
# Build etcd-cpp-api
# Build AWS SDK
# Build gusli

# Stage 4: Build NIXL
# Create Python venv with uv
# Build NIXL with -Dlibfabric_path=/usr/local
# Build and install wheel

# Stage 5: Optional NCCL (keep our approach)
# Build NCCL from source
# Build AWS OFI NCCL plugin

# Final stage: Runtime
# Copy all built libraries
# Set environment variables
# Install wheel
```

---

## Action Items

1. ✅ Create new Dockerfile based on official NIXL approach
2. ✅ Use libfabric v1.21.0 to `/usr/local`
3. ✅ Upgrade NIXL to 0.7.1
4. ✅ Use CUDA 12.9 + Ubuntu 24.04
5. ✅ Add DOCA for GPUNetIO
6. ✅ Add gusli for storage
7. ✅ Use uv for Python package management
8. ⚠️ Test that EFA kernel drivers work with source-built libfabric

---

## Testing Strategy

After building aligned container:

1. **Verify libfabric**: `ldd /usr/local/nixl/lib/x86_64-linux-gnu/plugins/libnixl_libfabric.so`
   - Should show: `libfabric.so.1 => /usr/local/lib/libfabric.so.1`

2. **Test NIXL**: `python -c "import nixl; print(nixl.__version__)"`
   - Should show: 0.7.1

3. **Test EFA**: `fi_info -p efa`
   - Should list EFA devices

4. **Test nixlbench**: `nixlbench --help`
   - Should work without segfaults

5. **Test vLLM disaggregation**: Deploy with NIXL
   - Should not segfault (unlike pip install)

---

## Files to Create

1. `Dockerfile.nixl-aligned` - New aligned Dockerfile
2. `build-nixl-aligned.sh` - Build script
3. `.dockerignore` - Exclude unnecessary files
4. `test-nixl-aligned.sh` - Validation script

---

## Version Summary for New Build

```bash
# Base
BASE_IMAGE="nvcr.io/nvidia/cuda-dl-base"
BASE_TAG="25.06-cuda12.9-devel-ubuntu24.04"

# Versions (from official NIXL)
NIXL_VERSION="0.7.1"
UCX_VERSION="v1.19.0"
LIBFABRIC_VERSION="v1.21.0"
PYTHON_VERSION="3.12"
RUST_VERSION="1.86.0"

# Paths (from official NIXL)
LIBFABRIC_INSTALL_PATH="/usr/local"
NIXL_PREFIX="/usr/local/nixl"
UCX_PREFIX="/usr"

# Additional (our additions)
EFA_VERSION="1.43.3"  # For kernel drivers only
GDRCOPY_VERSION="2.4.1"
NCCL_VERSION="2.23.4-1"  # Optional
```

This alignment should fix the segfault issue your friend identified while keeping EFA support working!
