# vLLM Testing - Ready to Deploy

## Summary

The vLLM container with Dynamo runtime is built and ready for testing. We've created all necessary files for GPU testing on your Kubernetes cluster.

## What's Ready

### Container Build ✅
- **Image**: `dynamo-vllm:slim`
- **Status**: Built successfully locally
- **Size**: ~17GB (optimized/debloated)
- **Components**:
  - vLLM 0.11.0
  - PyTorch 2.8.0+cu128
  - CUDA 12.9.1
  - Ray 2.51.1
  - NIXL networking stack
  - EFA drivers

### Test Files ✅
1. **test-vllm-local.py** - Python test script for vLLM inference
2. **examples/vllm-test-pod.yaml** - Kubernetes pod manifest
3. **examples/VLLM_TESTING.md** - Complete testing guide with troubleshooting

### Test Script Features ✅
- Syntax validated ✅
- Supports multiple small models (OPT-125M, GPT-2, Phi-2, TinyLlama)
- Command-line model selection
- Memory-efficient configuration (50% GPU memory, 512 token context)
- Clear output formatting with progress indicators

## Current Blocker

**AWS Credentials Expired** ❌
- Cannot push to ECR
- Cannot create ECR repository
- Need to refresh AWS credentials to proceed with cluster testing

## Next Steps (Once AWS Credentials Refreshed)

### Quick Start (5 minutes)

```bash
# 1. Create ECR repository and push image
aws ecr create-repository --repository-name dynamo-vllm --region us-east-2
docker tag dynamo-vllm:slim 058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-vllm:slim
docker push 058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-vllm:slim

# 2. Deploy test pod to Kubernetes
kubectl apply -f examples/vllm-test-pod.yaml
kubectl wait --for=condition=ready pod/vllm-test --timeout=120s

# 3. Copy test script and run
kubectl cp test-vllm-local.py vllm-test:/workspace/
kubectl exec vllm-test -- bash -c "source /opt/venv/bin/activate && python /workspace/test-vllm-local.py"

# 4. View results
kubectl logs vllm-test
```

### Alternative: Test Without ECR Push

If your Kubernetes nodes can access Docker on this machine:

```bash
# Use local image tag in vllm-test-pod.yaml (already configured)
kubectl apply -f examples/vllm-test-pod.yaml
kubectl cp test-vllm-local.py vllm-test:/workspace/
kubectl exec -it vllm-test -- bash
source /opt/venv/bin/activate
python /workspace/test-vllm-local.py
```

## Testing Options

### 1. Quick Validation (30 seconds)
```bash
python /workspace/test-vllm-local.py facebook/opt-125m
```
- Model: OPT-125M (~250MB)
- Downloads in ~10 seconds
- Runs 3 inference tests

### 2. Better Quality Test (2 minutes)
```bash
python /workspace/test-vllm-local.py TinyLlama/TinyLlama-1.1B-Chat-v1.0
```
- Model: TinyLlama-1.1B (~1.1GB)
- Better quality outputs
- Still fast to download and run

### 3. Production-Like Test (5 minutes)
```bash
python /workspace/test-vllm-local.py microsoft/phi-2
```
- Model: Phi-2 (~2.7GB)
- High-quality outputs
- Representative of production workloads

## Expected Output

Successful test will show:

```
================================================================================
Testing vLLM with facebook/opt-125m
================================================================================

1. Loading model: facebook/opt-125m
✅ Model loaded successfully

2. Running inference on 3 prompts...

3. Results:
================================================================================

Prompt: Hello, my name is
Generated: [AI-generated text]
--------------------------------------------------------------------------------

✅ vLLM test completed successfully!
================================================================================
```

## File Locations

```
/home/ubuntu/dynamo-workshop/
├── test-vllm-local.py                    # Test script
├── examples/
│   ├── vllm-test-pod.yaml               # Kubernetes pod manifest
│   └── VLLM_TESTING.md                  # Complete testing guide
└── VLLM_TEST_READY.md                   # This file
```

## Troubleshooting

### If AWS credentials expired:
```bash
# Get new credentials from AWS Console and set:
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

### If ECR repository already exists:
```bash
# Just push the image (skip create-repository)
docker push 058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-vllm:slim
```

### If pod fails to pull image:
```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-2 | \
  docker login --username AWS --password-stdin 058264135704.dkr.ecr.us-east-2.amazonaws.com
```

### If GPU not available:
```bash
# Check GPU resources in cluster
kubectl describe nodes | grep -A 10 "Allocated resources"

# Verify from within pod
kubectl exec vllm-test -- nvidia-smi
```

## Background Builds Status

Multiple container builds are still running in background:
- nixl-aligned rebuilds (6 processes)
- dynamo-base builds (3 processes)
- dynamo-vllm rebuilds (4 processes)
- dynamo-trtllm builds (2 processes)
- ECR pushes (various, awaiting credentials)

These can continue in background while you test vLLM.

## After Successful Test

Once vLLM testing is complete, you can:

1. **Test Multi-Node Setup**: Deploy vLLM with tensor parallelism across multiple nodes
2. **Benchmark Performance**: Use scripts in `benchmarks/` for throughput testing
3. **Test NIXL Integration**: Enable Dynamo's NIXL networking for distributed inference
4. **Production Deployment**: Use `scripts/deploy-dynamo-vllm.sh` for full production setup

See **BENCHMARKING_GUIDE.md** for complete production deployment workflow.

## Questions?

Refer to:
- **examples/VLLM_TESTING.md** - Complete testing guide
- **BENCHMARKING_GUIDE.md** - Production benchmarking
- **README.md** - Overall project documentation
- **PROJECT_STATUS_2025-11-10.md** - Project status and achievements
