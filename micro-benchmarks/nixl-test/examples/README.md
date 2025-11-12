# vLLM Deployment and Benchmarking Examples

This directory contains example configurations and templates for deploying and benchmarking vLLM with NVIDIA Dynamo.

## Files

- `deployment-env.sh` - Environment configuration template (source this first!)
- `vllm-deployment-example.yaml` - Example DynamoGraphDeployment YAML

## Quick Start

### 1. Set Up Environment

```bash
# Copy and edit the environment template
cp examples/deployment-env.sh examples/deployment-env-custom.sh
vim examples/deployment-env-custom.sh  # Edit for your cluster

# Source the environment
source examples/deployment-env-custom.sh
```

### 2. Create Kubernetes Secrets

```bash
# Create HuggingFace token secret
kubectl create secret generic hf-token-secret \
  --from-literal=HF_TOKEN=YOUR_HF_TOKEN_HERE \
  -n ${NAMESPACE}

# Verify secret was created
kubectl get secret hf-token-secret -n ${NAMESPACE}
```

### 3. Deploy vLLM

```bash
# Generate and deploy
./scripts/deploy-dynamo-vllm.sh

# Monitor deployment
kubectl get pods -n ${NAMESPACE} -l dynamoNamespace=${DEPLOYMENT_NAME} -w
```

### 4. Port Forward (in a separate terminal)

```bash
# Forward service to localhost
kubectl port-forward svc/${FRONTEND_SVC} 8080:8080 -n ${NAMESPACE}
```

### 5. Test Deployment

```bash
# Check health
curl http://localhost:8080/health

# Test completion
curl -X POST http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama/Llama-3.3-70B-Instruct",
    "prompt": "Write a poem about GPUs:",
    "max_tokens": 100,
    "temperature": 0.7
  }'
```

### 6. Run Benchmarks

```bash
# GenAI-Perf benchmark (client-side)
./scripts/benchmark-genai-perf.sh

# vLLM native benchmark (concurrency sweep)
./scripts/benchmark-vllm-native.sh
```

## Configuration Options

### Key Environment Variables

Edit `deployment-env.sh` to customize:

```bash
# Model Configuration
export MODEL_ID="meta-llama/Llama-3.3-70B-Instruct"
export TENSOR_PARALLEL_SIZE="8"  # Number of GPUs

# Memory Configuration
export MAX_MODEL_LEN="131072"  # Context window
export GPU_MEMORY_UTILIZATION="0.90"  # GPU memory usage
export KV_CACHE_DTYPE="fp8"  # KV cache precision

# Concurrency Configuration
export MAX_NUM_SEQS="64"  # Max concurrent sequences
```

### Architecture-Specific Builds

For different GPU architectures, update the container build:

```bash
# H100 (default)
export CUDA_ARCH="90"
export CUDA_ARCH_NAME="H100"

# A100
export CUDA_ARCH="80"
export CUDA_ARCH_NAME="A100"

# A10G
export CUDA_ARCH="86"
export CUDA_ARCH_NAME="A10G"
```

Then rebuild containers:
```bash
./build-all-slim.sh
```

## Troubleshooting

### Pods Stuck in Pending

```bash
# Check GPU availability
kubectl describe node | grep nvidia.com/gpu

# Check node resources
kubectl describe node <node-name>
```

### Readiness Probe Failures

```bash
# Check worker logs
kubectl logs -f ${WORKER_POD} -n ${NAMESPACE}

# Verify model download
kubectl exec ${WORKER_POD} -n ${NAMESPACE} -- ls -la /models/
```

### Port Forward Connection Refused

```bash
# Verify service exists
kubectl get svc -n ${NAMESPACE}

# Check service endpoints
kubectl get endpoints ${FRONTEND_SVC} -n ${NAMESPACE}
```

## Cleanup

```bash
# Delete deployment
kubectl delete dynamographdeployment ${DEPLOYMENT_NAME} -n ${NAMESPACE}

# Force delete stuck pods
kubectl delete pod ${WORKER_POD} -n ${NAMESPACE} --force --grace-period=0
```

## Additional Resources

- [Main Benchmarking Guide](../BENCHMARKING_GUIDE.md)
- [Container Build Guide](../README.md)
- [vLLM Documentation](https://github.com/vllm-project/vllm)
