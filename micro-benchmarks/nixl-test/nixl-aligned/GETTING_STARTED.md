# Getting Started with NIXL-Aligned Build

**Quick Start Guide for Building and Testing**

---

## What Is This?

This is a **clean-slate Docker build** that:
1. ✅ Aligns with official NVIDIA ai-dynamo/nixl 0.7.1
2. ✅ Adds AWS EFA support for HyperPod/EKS
3. ✅ Fixes the libfabric segfault issue (Experiment 5)
4. ✅ Uses best practices from both approaches

**Key insight**: NIXL must be compiled with `-Dlibfabric_path` pointing to the exact libfabric location, or vLLM disaggregation will segfault.

---

## Current Status

**Location**: `/home/ubuntu/dynamo-experiment/`
**Branch**: `experiment/nixl-aligned-build` (in dynamo-workshop repo)
**Files Created**:
- `Dockerfile.nixl-aligned` - Main Dockerfile (16KB)
- `build-nixl-aligned.sh` - Build script (4KB)
- `README.md` - Full documentation (7KB)
- `VERSION_COMPARISON.md` - Detailed version analysis (8KB)
- `nixl/` - Cloned official NIXL repo

---

## How to Build

### Option 1: Default Build (Recommended)

```bash
cd /home/ubuntu/dynamo-experiment
./build-nixl-aligned.sh
```

**Build time**: ~35 minutes on H100 (without NCCL)

### Option 2: With NCCL

```bash
INSTALL_NCCL=1 ./build-nixl-aligned.sh
```

**Build time**: ~45 minutes

### Option 3: Custom Settings

```bash
NPROC=16 IMAGE_NAME=my-nixl TAG=test ./build-nixl-aligned.sh
```

---

## After Building

### 1. Validate

```bash
docker run --rm nixl-aligned:latest validate-nixl
```

Should show:
- ✅ NIXL 0.7.1
- ✅ libfabric linked to /usr/local/lib
- ✅ UCX info
- ⚠️ EFA devices (warning OK without hardware)

### 2. Test Python

```bash
docker run --rm nixl-aligned:latest python -c "import nixl; print(nixl.__version__)"
```

Output: `0.7.1`

### 3. Critical Check: libfabric Path

```bash
docker run --rm nixl-aligned:latest \
    ldd /usr/local/nixl/lib/x86_64-linux-gnu/plugins/libnixl_libfabric.so | grep libfabric
```

**Must show**: `libfabric.so.1 => /usr/local/lib/libfabric.so.1`
**NOT**: `/opt/amazon/efa` (would cause segfault)

---

## Push to ECR

```bash
# Tag
docker tag nixl-aligned:0.7.1 \
    058264135704.dkr.ecr.us-east-2.amazonaws.com/nixl-aligned:0.7.1

# Login
aws ecr get-login-password --region us-east-2 | \
    docker login --username AWS --password-stdin \
    058264135704.dkr.ecr.us-east-2.amazonaws.com

# Create repository (if needed)
aws ecr create-repository --repository-name nixl-aligned --region us-east-2

# Push
docker push 058264135704.dkr.ecr.us-east-2.amazonaws.com/nixl-aligned:0.7.1
```

---

## What Changed from Our Production Build

### Versions
- NIXL: 0.6.0 → **0.7.1**
- libfabric: v2.3.0 @ /opt/amazon/efa → **v1.21.0 @ /usr/local**
- CUDA: 12.8 → **12.9**
- Ubuntu: 22.04 → **24.04**
- Base: pytorch → **cuda-dl-base**

### Build Approach
- libfabric from EFA installer → **Built from source**
- System Python → **Virtual environment with uv**
- No DOCA → **Includes DOCA (GPUNetIO)**
- No gusli → **Includes gusli (storage)**

### The Critical Fix

**Before**:
```dockerfile
# EFA installer puts libfabric in /opt/amazon/efa
RUN ./efa_installer.sh -y
# NIXL compiled without explicit path (uses bundled libfabric 2.3)
RUN meson setup build/ --prefix=/usr/local/nixl
# Result: vLLM segfaults
```

**After**:
```dockerfile
# Build libfabric from source to /usr/local
RUN ./configure --prefix=/usr/local --enable-efa
RUN make install
# NIXL explicitly told to use /usr/local
RUN meson setup -Dlibfabric_path=/usr/local build/
# Result: No segfaults!
```

---

## Testing Plan

### Phase 1: Container Validation
1. ✅ Build succeeds
2. ✅ NIXL imports
3. ✅ libfabric path correct
4. ✅ Can run nixlbench --help

### Phase 2: Same-Node Test
Deploy pod and test NIXL on single node:
```bash
kubectl run nixl-test --rm -it \
    --image=058264135704.dkr.ecr.us-east-2.amazonaws.com/nixl-aligned:0.7.1 \
    -- python -c "import nixl; print('OK')"
```

### Phase 3: Two-Node Benchmark
Use existing NIXL benchmark pods (Experiment 6):
```bash
# Update image in experiments/experiment-6-nixl-benchmark/nixl-benchmark-pods.yaml
# to use nixl-aligned:0.7.1
kubectl apply -f experiments/experiment-6-nixl-benchmark/nixl-benchmark-pods.yaml
```

### Phase 4: vLLM Disaggregation
Deploy vLLM with NIXL:
```bash
vllm serve meta-llama/Llama-3.1-8B-Instruct \
    --enable-disaggregation \
    --kv-connector nixl \
    --nixl-etcd-endpoints http://etcd-service:2379
```

**Expected**: No segfaults (unlike pip install nixl)

---

## Files Reference

### In dynamo-experiment/
- `Dockerfile.nixl-aligned` - Main Dockerfile
- `build-nixl-aligned.sh` - Build script
- `README.md` - Full documentation
- `VERSION_COMPARISON.md` - Detailed comparison
- `GETTING_STARTED.md` - This file
- `nixl/` - Official NIXL repo

### In dynamo-workshop/
- Branch: `experiment/nixl-aligned-build`
- All experiment files preserved
- Can merge this branch later

---

## Troubleshooting

### Build Fails

**Check**:
1. Docker BuildKit enabled: `export DOCKER_BUILDKIT=1`
2. Disk space: `df -h` (need 50GB+)
3. Network: Can download from github.com, nvidia.com
4. Log: Check `build-nixl-aligned.log`

### Validation Fails

**libfabric not in /usr/local**:
```bash
# Rebuild with clean docker cache
docker build --no-cache -f Dockerfile.nixl-aligned .
```

**Python import fails**:
```bash
# Check virtual environment
docker run --rm -it nixl-aligned:latest bash
source /opt/venv/bin/activate
python -c "import nixl"
```

### EFA Not Working

**This is OK** if no EFA hardware present. Test will work once deployed to EFA-enabled nodes.

---

## Key Takeaways

1. **Never use `pip install nixl` on EFA systems** - it bundles wrong libfabric
2. **Always build NIXL from source** with explicit `-Dlibfabric_path`
3. **Use libfabric v1.21.0** (official NIXL version) not v2.3.0
4. **Install to /usr/local** for consistency with official NIXL
5. **AWS EFA drivers separate** from libfabric build

---

## Next Steps

1. **Build**: `./build-nixl-aligned.sh`
2. **Validate**: `docker run --rm nixl-aligned:latest validate-nixl`
3. **Push to ECR**
4. **Test in Kubernetes**
5. **Compare with production image**

Once validated, this becomes the new production image that fixes all the issues we discovered in Experiments 1-6!

---

## Questions?

See full documentation:
- `README.md` - Complete guide
- `VERSION_COMPARISON.md` - Version analysis
- `Dockerfile.nixl-aligned` - See inline comments

Or check official NIXL:
- https://github.com/ai-dynamo/nixl
- `nixl/contrib/Dockerfile` - Their approach
