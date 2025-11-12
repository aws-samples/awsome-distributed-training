# vLLM Testing Guide

## Overview

This guide explains how to test vLLM with a small language model on your Kubernetes cluster.

## Prerequisites

1. AWS credentials configured
2. kubectl access to cluster
3. vLLM container built locally: `dynamo-vllm:slim`
4. Test script: `test-vllm-local.py`

## Option 1: Quick Test (No ECR Push Required)

If your Kubernetes nodes can access the Docker daemon on this machine, you can test directly:

```bash
# 1. Deploy test pod (uses local image)
kubectl apply -f examples/vllm-test-pod.yaml

# 2. Wait for pod to be ready
kubectl wait --for=condition=ready pod/vllm-test --timeout=120s

# 3. Check pod status
kubectl get pod vllm-test
kubectl logs vllm-test

# 4. Copy test script to pod
kubectl cp test-vllm-local.py vllm-test:/workspace/

# 5. Run test interactively
kubectl exec -it vllm-test -- bash
source /opt/venv/bin/activate
python /workspace/test-vllm-local.py

# 6. Or run test non-interactively
kubectl exec vllm-test -- bash -c "source /opt/venv/bin/activate && python /workspace/test-vllm-local.py"

# 7. Cleanup
kubectl delete pod vllm-test
```

## Option 2: Production Test (With ECR)

For testing with ECR (requires valid AWS credentials):

```bash
# 1. Create ECR repository
aws ecr create-repository --repository-name dynamo-vllm --region us-east-2

# 2. Tag and push image
docker tag dynamo-vllm:slim 058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-vllm:slim
docker push 058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-vllm:slim

# 3. Update vllm-test-pod.yaml to use ECR image
# Change image line to:
#   image: 058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-vllm:slim

# 4. Deploy and test (same as Option 1)
kubectl apply -f examples/vllm-test-pod.yaml
```

## Test Models

The test script supports multiple small models:

### Tiny Models (Fastest, ~250-500MB)
```bash
# OPT-125M (default)
python /workspace/test-vllm-local.py facebook/opt-125m

# GPT-2
python /workspace/test-vllm-local.py gpt2
```

### Small Models (~1-3GB)
```bash
# TinyLlama
python /workspace/test-vllm-local.py TinyLlama/TinyLlama-1.1B-Chat-v1.0

# Phi-2
python /workspace/test-vllm-local.py microsoft/phi-2
```

## Expected Output

Successful test output should look like:

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
Generated: John and I am a software engineer...
--------------------------------------------------------------------------------

Prompt: The capital of France is
Generated: Paris, which is known for...
--------------------------------------------------------------------------------

Prompt: In a galaxy far far away,
Generated: there lived a brave...
--------------------------------------------------------------------------------

✅ vLLM test completed successfully!
================================================================================
```

## Troubleshooting

### Pod fails to start
```bash
# Check pod events
kubectl describe pod vllm-test

# Check logs
kubectl logs vllm-test
```

### Image pull errors
```bash
# If using ECR, check authentication
aws ecr get-login-password --region us-east-2 | \
  docker login --username AWS --password-stdin 058264135704.dkr.ecr.us-east-2.amazonaws.com
```

### GPU not detected
```bash
# Verify GPU resources are available
kubectl describe nodes | grep -A 10 "Allocated resources"

# Check GPU from within pod
kubectl exec vllm-test -- nvidia-smi
```

### Out of memory
```bash
# Use smaller model or reduce max_model_len
# In test-vllm-local.py, line 19:
#   max_model_len=512  # Reduce from 512 to 256
```

## Current Status

**Container Build Status:**
- ✅ dynamo-vllm:slim built successfully locally
- ❌ ECR push pending (AWS credentials expired)
- ✅ Test script validated: test-vllm-local.py

**Test Script:**
- Location: `/home/ubuntu/dynamo-workshop/test-vllm-local.py`
- Syntax: ✅ Validated
- Default model: facebook/opt-125m (~250MB)

**Next Steps:**
1. Refresh AWS credentials
2. Push image to ECR
3. Deploy test pod
4. Run inference test

## Integration with Dynamo

Once vLLM testing is complete, you can test with NIXL networking:

```bash
# Deploy vLLM with NIXL coordination (multi-node)
# See BENCHMARKING_GUIDE.md for production deployment
```
