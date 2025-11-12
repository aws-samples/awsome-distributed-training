# vLLM Benchmarking Guide for NVIDIA Dynamo

This guide provides scripts and instructions for benchmarking vLLM inference with NVIDIA Dynamo on AWS GPU instances.

## Overview

This guide covers:
- Deploying vLLM with NVIDIA Dynamo runtime
- Running GenAI-Perf (client-side) benchmarks
- Running vLLM native (in-cluster) benchmarks
- Collecting and analyzing performance metrics

## Prerequisites

- Kubernetes cluster with NVIDIA GPU nodes (H100, A100, or A10G)
- NVIDIA GPU Operator installed
- Hugging Face account with access to gated models
- `kubectl` configured for your cluster
- Docker installed locally (for GenAI-Perf)

## Quick Start

1. **Set up environment**:
```bash
# Source the environment configuration
source examples/deployment-env.sh

# Create Kubernetes secrets
kubectl create secret generic hf-token-secret \
  --from-literal=HF_TOKEN=YOUR_HF_TOKEN_HERE \
  -n ${NAMESPACE}
```

2. **Deploy vLLM**:
```bash
# Generate and deploy
./scripts/deploy-dynamo-vllm.sh
```

3. **Run benchmarks**:
```bash
# GenAI-Perf benchmark
./scripts/benchmark-genai-perf.sh

# vLLM native benchmark
./scripts/benchmark-vllm-native.sh
```

## Architecture Support

| GPU  | CUDA Arch | AWS Instance | Build Flag |
|------|-----------|--------------|------------|
| H100 | 90 (SM90) | p5.*        | `CUDA_ARCH=90 CUDA_ARCH_NAME=H100` |
| A100 | 80 (SM80) | p4d.*       | `CUDA_ARCH=80 CUDA_ARCH_NAME=A100` |
| A10G | 86 (SM86) | g5.*        | `CUDA_ARCH=86 CUDA_ARCH_NAME=A10G` |

## Deployment Configuration

### Environment Variables

Key configuration parameters (edit `examples/deployment-env.sh`):

```bash
# Model Configuration
export MODEL_ID="meta-llama/Llama-3.3-70B-Instruct"
export TENSOR_PARALLEL_SIZE="8"

# Memory & Context
export MAX_MODEL_LEN="131072"
export GPU_MEMORY_UTILIZATION="0.90"
export KV_CACHE_DTYPE="fp8"

# Concurrency
export MAX_NUM_SEQS="64"
export MAX_NUM_SEQS_PREFILL="1"
export MAX_NUM_SEQS_DECODE="64"
```

### Deployment Modes

**Aggregated Mode** (default):
- Single worker pool handles both prefill and decode
- Simpler setup, good for smaller deployments
- Use when: Testing, single-node, or low concurrency

**Disaggregated Mode**:
- Separate prefill and decode workers
- Better scaling for high throughput
- Use when: Multi-node, high concurrency (>50 concurrent requests)

## Benchmark Types

### 1. GenAI-Perf (Client-Side)

Measures end-to-end latency from client perspective:
- Time to First Token (TTFT)
- Inter-Token Latency (ITL)
- Request throughput
- GPU utilization

**When to use**: Production load simulation, user-facing performance validation

```bash
./scripts/benchmark-genai-perf.sh
```

Results location: `artifacts/` and `exports/`

### 2. vLLM Native Benchmark

Sweeps concurrency levels to measure scaling:
- Concurrency: 1, 2, 4, 8, 16, 32, 48, 64
- Fixed input/output token lengths
- Detailed latency percentiles

**When to use**: Capacity planning, scaling validation, bottleneck analysis

```bash
./scripts/benchmark-vllm-native.sh
```

Results location: `results/vllm_benchmark_*.json`

## Key Metrics

| Metric | Description | Target (H100, 15k context) |
|--------|-------------|---------------------------|
| **TTFT p99** | Time to first token | < 1500ms |
| **ITL p50** | Inter-token latency | < 50ms |
| **Throughput** | Requests/second | > 20 RPS @ 16 concurrency |
| **GPU Util** | Compute utilization | > 85% |

## Monitoring

### Check Deployment Status

```bash
# Pod status
kubectl get pods -n ${NAMESPACE} -l dynamoNamespace=${DEPLOYMENT_NAME}

# Logs
kubectl logs -f ${WORKER_POD} -n ${NAMESPACE}

# GPU utilization
kubectl exec ${WORKER_POD} -n ${NAMESPACE} -- nvidia-smi
```

### Port Forwarding

```bash
# Forward service to localhost
kubectl port-forward svc/${FRONTEND_SVC} 8080:8080 -n ${NAMESPACE}

# Test health endpoint
curl http://localhost:8080/health
```

## Troubleshooting

### Common Issues

**Pods stuck in Pending**:
```bash
# Check GPU availability
kubectl describe node <node-name> | grep nvidia.com/gpu
```

**Readiness probe failures**:
```bash
# Check worker logs for errors
kubectl logs ${WORKER_POD} -n ${NAMESPACE} --tail=100

# Verify model download
kubectl exec ${WORKER_POD} -n ${NAMESPACE} -- ls -la /models/
```

**Low throughput**:
- Reduce `GPU_MEMORY_UTILIZATION` by 0.05
- Adjust `MAX_NUM_SEQS` based on available memory
- Enable `ENABLE_PREFIX_CACHING=true`

**NCCL errors**:
```bash
# Set debug logging
kubectl set env deployment/${DEPLOYMENT_NAME}-worker NCCL_DEBUG=INFO -n ${NAMESPACE}

# Check NVLink topology
kubectl exec ${WORKER_POD} -n ${NAMESPACE} -- nvidia-smi topo -m
```

## Results Collection

### GenAI-Perf Artifacts

```
artifacts/
├── standard/
│   ├── metrics.csv          # Latency breakdown
│   ├── throughput.png       # Throughput plot
│   └── latency_dist.png     # Latency distribution
exports/
└── standard.json            # Machine-readable profile
```

### vLLM Benchmark Results

```
results/
├── vllm_benchmark_102k_context_1prompts.json
├── vllm_benchmark_102k_context_2prompts.json
├── ...
└── vllm_benchmark_102k_context_64prompts.json
```

### Copy Results

```bash
# From pod to local
kubectl cp ${WORKER_POD}:/workspace/results/ ./results/ -n ${NAMESPACE}

# Upload to S3 (optional)
aws s3 sync ./results/ s3://your-bucket/benchmarks/$(date +%Y%m%d)/
```

## Advanced Configuration

### Multi-Node Deployment

For multi-node setups:

1. Update node selector in deployment YAML
2. Verify inter-node networking (NCCL tests)
3. Set appropriate `NCCL_SOCKET_IFNAME`

### Custom Models

To use custom models:

1. Update `MODEL_ID` in `examples/deployment-env.sh`
2. Adjust `TENSOR_PARALLEL_SIZE` based on model size
3. Update `MAX_MODEL_LEN` for context window
4. Set `TRUST_REMOTE_CODE=true` if needed

### Memory Optimization

Balance memory vs. throughput:

```bash
# More memory for KV cache (higher throughput)
export GPU_MEMORY_UTILIZATION="0.95"
export KV_CACHE_DTYPE="auto"

# Less memory (more stable)
export GPU_MEMORY_UTILIZATION="0.85"
export KV_CACHE_DTYPE="fp8"
```

## Performance Tuning

### Prefill/Decode Balance

For disaggregated mode:

```bash
# More prefill capacity (long prompts)
export MAX_NUM_SEQS_PREFILL="4"
export MAX_NUM_SEQS_DECODE="32"

# More decode capacity (short prompts, long outputs)
export MAX_NUM_SEQS_PREFILL="1"
export MAX_NUM_SEQS_DECODE="64"
```

### Batching Strategy

```bash
# Larger batches (higher throughput, more latency)
export MAX_NUM_SEQS="128"

# Smaller batches (lower latency, less throughput)
export MAX_NUM_SEQS="32"
```

## References

- [vLLM GitHub](https://github.com/vllm-project/vllm)
- [NVIDIA Triton GenAI-Perf](https://github.com/triton-inference-server/client/tree/main/src/c%2B%2B/perf_analyzer/genai-perf)
- [Kubernetes GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [NCCL Tests](https://github.com/NVIDIA/nccl-tests)

## Quick Command Reference

```bash
# Deploy
./scripts/deploy-dynamo-vllm.sh

# Run benchmarks
./scripts/benchmark-genai-perf.sh
./scripts/benchmark-vllm-native.sh

# Check status
kubectl get pods -n ${NAMESPACE}
kubectl logs -f ${WORKER_POD} -n ${NAMESPACE}

# Port forward
kubectl port-forward svc/${FRONTEND_SVC} 8080:8080 -n ${NAMESPACE}

# Test API
curl -X POST http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "meta-llama/Llama-3.3-70B-Instruct", "prompt": "Hello", "max_tokens": 50}'

# Cleanup
kubectl delete dynamographdeployment ${DEPLOYMENT_NAME} -n ${NAMESPACE}
```
