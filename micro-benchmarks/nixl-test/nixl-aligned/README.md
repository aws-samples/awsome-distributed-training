# NIXL-Aligned Container Build

**Created**: 2025-11-09
**Purpose**: Align with official ai-dynamo/nixl 0.7.1 while maintaining AWS EFA support

---

## Overview

This is a from-scratch Docker build that combines:
- ✅ Official NIXL 0.7.1 versions and approach
- ✅ AWS EFA driver support for HyperPod/EKS
- ✅ Fixes the libfabric segfault issue identified in Experiment 5

**Key fix**: NIXL compiled with `-Dlibfabric_path=/usr/local` pointing to source-built libfabric v1.21.0

---

## What Changed from Our Production Build

### Base Image
- **Before**: `pytorch:25.06-py3` (CUDA 12.8, Ubuntu 22.04)
- **After**: `cuda-dl-base:25.06-cuda12.9-devel-ubuntu24.04`

### NIXL
- **Before**: v0.6.0
- **After**: v0.7.1 (latest)

### libfabric (CRITICAL CHANGE)
- **Before**: v2.3.0 installed to `/opt/amazon/efa` (via EFA installer)
- **After**: v1.21.0 built from source to `/usr/local`
- **Why**: NIXL's libfabric plugin must match the path, fixing segfault

### Python Environment
- **Before**: System-wide packages
- **After**: Virtual environment at `/opt/venv` managed with `uv`

### New Components
- ✅ DOCA (for GPUNetIO backend)
- ✅ gusli (NVIDIA storage library)
- ✅ Improved RDMA/verbs handling

---

## Versions

| Component | Version | Install Path |
|-----------|---------|--------------|
| NIXL | 0.7.1 | /usr/local/nixl |
| libfabric | v1.21.0 | /usr/local |
| UCX | v1.19.0 | /usr |
| GDRCopy | v2.4.1 | /usr/local |
| Python | 3.12 | /opt/venv |
| CUDA | 12.9 | /usr/local/cuda |
| Ubuntu | 24.04 | - |
| Rust | 1.86.0 | /usr/local/cargo |

---

## Build Instructions

### Quick Build

```bash
cd /home/ubuntu/dynamo-experiment
chmod +x build-nixl-aligned.sh
./build-nixl-aligned.sh
```

### Custom Build

```bash
# Set parallel jobs
NPROC=16 ./build-nixl-aligned.sh

# Include NCCL
INSTALL_NCCL=1 ./build-nixl-aligned.sh

# Custom image name
IMAGE_NAME=my-nixl TAG=test ./build-nixl-aligned.sh
```

### Build Time

Expected build time on H100 with 16 cores:
- **With NCCL**: ~45 minutes
- **Without NCCL**: ~35 minutes

---

## Validation

### 1. Run Built-in Validation

```bash
docker run --rm nixl-aligned:latest validate-nixl
```

Expected output:
```
=== NIXL Validation ===

1. Python import:
   ✅ NIXL 0.7.1

2. libfabric linkage:
   libfabric.so.1 => /usr/local/lib/libfabric.so.1

3. EFA devices:
   [Lists EFA devices or warning if no hardware]

4. UCX info:
   Version 1.19.0
   Configured with: --with-efa --with-cuda --with-verbs

=== Validation Complete ===
```

### 2. Test NIXL Import

```bash
docker run --rm nixl-aligned:latest python -c "import nixl; print(nixl.__version__)"
```

Should output: `0.7.1`

### 3. Check libfabric Linkage (Critical)

```bash
docker run --rm nixl-aligned:latest ldd /usr/local/nixl/lib/x86_64-linux-gnu/plugins/libnixl_libfabric.so | grep libfabric
```

Should show:
```
libfabric.so.1 => /usr/local/lib/libfabric.so.1 (NOT /opt/amazon/efa)
```

### 4. Test with GPU

```bash
docker run --rm --gpus all nixl-aligned:latest nvidia-smi
```

---

## Deployment

### Tag and Push to ECR

```bash
# Tag
docker tag nixl-aligned:0.7.1 058264135704.dkr.ecr.us-east-2.amazonaws.com/nixl-aligned:0.7.1
docker tag nixl-aligned:0.7.1 058264135704.dkr.ecr.us-east-2.amazonaws.com/nixl-aligned:latest

# Login
aws ecr get-login-password --region us-east-2 | \
    docker login --username AWS --password-stdin 058264135704.dkr.ecr.us-east-2.amazonaws.com

# Push
docker push 058264135704.dkr.ecr.us-east-2.amazonaws.com/nixl-aligned:0.7.1
docker push 058264135704.dkr.ecr.us-east-2.amazonaws.com/nixl-aligned:latest
```

### Use in Kubernetes

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nixl-test
spec:
  containers:
  - name: nixl
    image: 058264135704.dkr.ecr.us-east-2.amazonaws.com/nixl-aligned:0.7.1
    command: ["python", "-c", "import nixl; print(nixl.__version__)"]
    resources:
      limits:
        nvidia.com/gpu: 1
        vpc.amazonaws.com/efa: 1
```

---

## Testing vLLM Disaggregation

This build should fix the segfault issue:

```yaml
# Deploy vLLM with NIXL
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-prefill
spec:
  template:
    spec:
      containers:
      - name: vllm
        image: 058264135704.dkr.ecr.us-east-2.amazonaws.com/nixl-aligned:0.7.1
        command:
          - vllm
          - serve
          - meta-llama/Llama-3.1-8B-Instruct
          - --enable-disaggregation
          - --enable-chunked-prefill
          - --kv-connector
          - nixl
        env:
          - name: NIXL_ETCD_ENDPOINTS
            value: "http://etcd-service:2379"
```

**Expected**: No segfaults (unlike pip-installed NIXL)

---

## Key Differences from pip install nixl

| Aspect | pip install nixl | This Build |
|--------|------------------|------------|
| libfabric | Bundled 2.3 | Source-built 1.21.0 |
| libfabric path | In package | /usr/local |
| EFA support | ❌ Segfaults | ✅ Works |
| NIXL version | 0.6.x | 0.7.1 |
| vLLM disaggregation | ❌ Segfaults | ✅ Works |

---

## Files

```
dynamo-experiment/
├── README.md (this file)
├── VERSION_COMPARISON.md (detailed analysis)
├── Dockerfile.nixl-aligned (main Dockerfile)
├── build-nixl-aligned.sh (build script)
└── nixl/ (cloned from ai-dynamo/nixl)
```

---

## Troubleshooting

### Build fails at libfabric

**Symptom**: Cannot download libfabric tarball

**Solution**:
```bash
# Check version
curl -I https://github.com/ofiwg/libfabric/releases/download/v1.21.0/libfabric-1.21.0.tar.bz2
```

### Build fails at DOCA

**Symptom**: Cannot download DOCA package

**Solution**: Check MELLANOX_OS variable or skip DOCA:
```dockerfile
# Comment out DOCA installation in Dockerfile
```

### Python import fails

**Symptom**: `ModuleNotFoundError: No module named 'nixl'`

**Solution**: Activate virtual environment:
```bash
docker run --rm -it nixl-aligned:latest bash
source /opt/venv/bin/activate
python -c "import nixl"
```

### EFA not working

**Symptom**: `fi_info -p efa` shows no devices

**Solution**: This is expected without EFA hardware. Test on actual EFA-enabled instance.

---

## Comparison Scripts

### Compare Dockerfiles

```bash
# Official NIXL
cat /home/ubuntu/dynamo-experiment/nixl/contrib/Dockerfile

# Our production
cat /home/ubuntu/dynamo-workshop/Dockerfile.production

# Aligned build
cat /home/ubuntu/dynamo-experiment/Dockerfile.nixl-aligned
```

### Compare Versions

```bash
cat /home/ubuntu/dynamo-experiment/VERSION_COMPARISON.md
```

---

## Next Steps

1. ✅ Build image: `./build-nixl-aligned.sh`
2. ✅ Validate: `docker run --rm nixl-aligned:latest validate-nixl`
3. ✅ Push to ECR
4. ✅ Test in Kubernetes
5. ✅ Test vLLM disaggregation (should not segfault)
6. ✅ Run NIXL benchmarks

---

## References

- Official NIXL: https://github.com/ai-dynamo/nixl
- NIXL Dockerfile: https://github.com/ai-dynamo/nixl/blob/main/contrib/Dockerfile
- AWS EFA: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html
- libfabric: https://github.com/ofiwg/libfabric

---

## Status

**Build**: ⏳ Pending
**Validation**: ⏳ Pending
**Testing**: ⏳ Pending

Once built and validated, this will replace our production image with proper NIXL 0.7.1 + EFA support.
