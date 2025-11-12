# NIXL Benchmark Testing Guide

Complete step-by-step instructions for running nixlbench on AWS SageMaker HyperPod.

**Date**: November 10, 2025
**Cluster**: AWS SageMaker HyperPod (us-east-2)
**Container**: nixl-aligned:0.7.1-bench

================================================================================
## PREREQUISITES
================================================================================

1. **kubectl** access to the HyperPod cluster
2. **AWS credentials** properly configured
3. **ETCD service** deployed (etcd-service)
4. **Test pods** deployed (efa-test-prefill, efa-test-decode)

================================================================================
## STEP 1: VERIFY CLUSTER ACCESS
================================================================================

Run these commands in your kubectl terminal:

```bash
# 1.1 Check cluster connection
kubectl cluster-info

# 1.2 Verify ETCD service is running
kubectl get svc etcd-service -n default

# Expected output:
# NAME            TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
# etcd-service    ClusterIP   10.100.xxx.xxx   <none>        2379/TCP,2380/TCP   Xh

# 1.3 Verify ETCD pod is running
kubectl get pods -l app=etcd -n default

# Expected output:
# NAME                    READY   STATUS    RESTARTS   AGE
# etcd-xxxxxxxxxx-xxxxx   1/1     Running   0          Xh

# 1.4 Verify test pods are running
kubectl get pods -l app=efa-test -n default -o wide

# Expected output:
# NAME                 READY   STATUS    NODE                                IP            
# efa-test-prefill     1/1     Running   hyperpod-i-0c3671963bb78e7ef       10.1.238.41   
# efa-test-decode      1/1     Running   hyperpod-i-0d7f064c7424c5dfd       10.1.159.225  
```

**OUTCOME**: 
- If ETCD service is missing → Deploy: `kubectl apply -f examples/etcd-deployment.yaml`
- If test pods are missing → Deploy: `kubectl apply -f examples/efa-test-pods.yaml`
- If pods show "ImagePullBackOff" → ECR authentication issue, check AWS credentials

================================================================================
## STEP 2: VERIFY NIXLBENCH IS INSTALLED
================================================================================

```bash
# 2.1 Check nixlbench is available in prefill pod
kubectl exec -it efa-test-prefill -- which nixlbench

# Expected output:
# /usr/local/bin/nixlbench

# 2.2 Check nixlbench version
kubectl exec -it efa-test-prefill -- nixlbench --help | head -n 5

# Expected output:
# NIXLBench - NVIDIA Inference Xfer Library Benchmark
# Usage: nixlbench [OPTIONS]
# ...
```

**OUTCOME**:
- If "nixlbench: not found" → Wrong container image, pods need `:0.7.1-bench` tag
- If command works → nixlbench is ready

================================================================================
## STEP 3: VERIFY ETCD CONNECTIVITY
================================================================================

```bash
# 3.1 Test ETCD connectivity from prefill pod
kubectl exec -it efa-test-prefill -- curl -s http://etcd-service:2379/version

# Expected output (JSON):
# {"etcdserver":"3.5.18","etcdcluster":"3.5.0"}

# 3.2 Test ETCD connectivity from decode pod
kubectl exec -it efa-test-decode -- curl -s http://etcd-service:2379/version

# Expected output (JSON):
# {"etcdserver":"3.5.18","etcdcluster":"3.5.0"}
```

**OUTCOME**:
- If "Could not resolve host" → DNS issue, check service name
- If "Connection refused" → ETCD not running, redeploy ETCD
- If JSON returned → ETCD connectivity working

================================================================================
## STEP 4: RUN NIXLBENCH - UCX BACKEND (GPU-to-GPU)
================================================================================

### Option A: Launch Both Workers Simultaneously (Recommended)

Open **TWO separate terminal windows** with kubectl access.

**Terminal 1** (Prefill Pod - Initiator):
```bash
kubectl exec -it efa-test-prefill -- bash -c '
echo "Starting nixlbench on PREFILL pod (initiator)..."
nixlbench \
  --etcd_endpoints http://etcd-service:2379 \
  --backend UCX \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --start_block_size 4096 \
  --max_block_size 67108864 \
  --num_iter 1000 \
  --warmup_iter 100 \
  --device_list mlx5_0
'
```

**Terminal 2** (Decode Pod - Target):
```bash
kubectl exec -it efa-test-decode -- bash -c '
echo "Starting nixlbench on DECODE pod (target)..."
nixlbench \
  --etcd_endpoints http://etcd-service:2379 \
  --backend UCX \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --start_block_size 4096 \
  --max_block_size 67108864 \
  --num_iter 1000 \
  --warmup_iter 100 \
  --device_list mlx5_0
'
```

**Instructions**:
1. Launch Terminal 2 FIRST (target must be ready)
2. Wait 5 seconds
3. Launch Terminal 1 (initiator connects to target)
4. Both terminals will show benchmark progress
5. Wait for completion (~2-5 minutes)

### Option B: Launch Workers Sequentially (Alternative)

```bash
# Step 4.1: Start decode pod (target) in background
kubectl exec -d efa-test-decode -- bash -c '
nixlbench \
  --etcd_endpoints http://etcd-service:2379 \
  --backend UCX \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --start_block_size 4096 \
  --max_block_size 67108864 \
  --num_iter 1000 \
  --warmup_iter 100 \
  --device_list mlx5_0 \
  > /tmp/nixlbench-decode.log 2>&1
'

# Step 4.2: Wait 10 seconds for target to initialize
sleep 10

# Step 4.3: Start prefill pod (initiator) and monitor output
kubectl exec -it efa-test-prefill -- bash -c '
nixlbench \
  --etcd_endpoints http://etcd-service:2379 \
  --backend UCX \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --start_block_size 4096 \
  --max_block_size 67108864 \
  --num_iter 1000 \
  --warmup_iter 100 \
  --device_list mlx5_0
'

# Step 4.4: Check decode pod logs
kubectl exec -it efa-test-decode -- cat /tmp/nixlbench-decode.log
```

**Expected Output** (on initiator terminal):
```
Connecting to ETCD at http://etcd-service:2379
Successfully connected to ETCD
Worker coordination successful (2 workers)
Starting benchmark with UCX backend...

Block Size: 4096 bytes
  Bandwidth: XX.XX GB/s
  Latency: X.XXX ms
  
Block Size: 8192 bytes
  Bandwidth: XX.XX GB/s
  Latency: X.XXX ms
  
...

Block Size: 67108864 bytes (64 MB)
  Bandwidth: XXX.XX GB/s
  Latency: X.XXX ms

Benchmark complete!
```

================================================================================
## STEP 5: RUN NIXLBENCH - LIBFABRIC BACKEND (EFA)
================================================================================

```bash
# Terminal 1 (Prefill)
kubectl exec -it efa-test-prefill -- bash -c '
nixlbench \
  --etcd_endpoints http://etcd-service:2379 \
  --backend LIBFABRIC \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --start_block_size 4096 \
  --max_block_size 67108864 \
  --num_iter 1000 \
  --warmup_iter 100
'

# Terminal 2 (Decode)
kubectl exec -it efa-test-decode -- bash -c '
nixlbench \
  --etcd_endpoints http://etcd-service:2379 \
  --backend LIBFABRIC \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --start_block_size 4096 \
  --max_block_size 67108864 \
  --num_iter 1000 \
  --warmup_iter 100
'
```

================================================================================
## STEP 6: RUN NIXLBENCH - MULTI-THREADED TEST
================================================================================

```bash
# Terminal 1 (Prefill)
kubectl exec -it efa-test-prefill -- bash -c '
nixlbench \
  --etcd_endpoints http://etcd-service:2379 \
  --backend UCX \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --num_threads 4 \
  --enable_pt \
  --progress_threads 2 \
  --start_block_size 4096 \
  --max_block_size 67108864 \
  --num_iter 1000 \
  --warmup_iter 100
'

# Terminal 2 (Decode)
kubectl exec -it efa-test-decode -- bash -c '
nixlbench \
  --etcd_endpoints http://etcd-service:2379 \
  --backend UCX \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --num_threads 4 \
  --enable_pt \
  --progress_threads 2 \
  --start_block_size 4096 \
  --max_block_size 67108864 \
  --num_iter 1000 \
  --warmup_iter 100
'
```

================================================================================
## TROUBLESHOOTING
================================================================================

### Problem: "Failed to acquire lock: the target uri is not valid"

**Cause**: ETCD endpoint configuration issue

**Solution**:
```bash
# Check pod environment variables
kubectl exec -it efa-test-prefill -- env | grep ETCD

# Expected:
# NIXL_ETCD_ENDPOINTS=http://etcd-service:2379
# NIXL_ETCD_NAMESPACE=/nixl/agents

# If incorrect, update examples/efa-test-pods.yaml and redeploy
kubectl delete pod efa-test-prefill efa-test-decode
kubectl apply -f examples/efa-test-pods.yaml
```

### Problem: "Connection timeout" or "ETCD not responding"

**Solution**:
```bash
# Restart ETCD
kubectl delete pod -l app=etcd
kubectl get pods -l app=etcd -w  # Wait for new pod to be Running

# Test connectivity again
kubectl exec -it efa-test-prefill -- curl http://etcd-service:2379/version
```

### Problem: "UCX device not found"

**Solution**:
```bash
# List available UCX devices
kubectl exec -it efa-test-prefill -- ucx_info -d

# Use device from output (e.g., mlx5_0, rdmap113s0)
# Specify in nixlbench: --device_list <device_name>
```

### Problem: "Worker coordination failed"

**Cause**: Both workers not started within coordination timeout

**Solution**:
- Launch target (decode) pod FIRST
- Launch initiator (prefill) pod within 30 seconds
- Ensure both pods use same --etcd_endpoints and --backend

================================================================================
## INTERPRETING RESULTS
================================================================================

### UCX Performance Expectations (H100 + EFA)

| Block Size | Expected Bandwidth | Expected Latency |
|------------|-------------------|------------------|
| 4 KB       | ~0.5 GB/s        | ~0.008 ms       |
| 64 KB      | ~8 GB/s          | ~0.010 ms       |
| 1 MB       | ~120 GB/s        | ~0.015 ms       |
| 64 MB      | ~280 GB/s        | ~0.230 ms       |

### Comparison with UCX Tools

UCX native tools (ucx_perftest) achieved: **284.98 GB/s** for 100MB transfers

nixlbench should show similar performance for large block sizes.

================================================================================
## CLEANUP
================================================================================

```bash
# Delete test pods
kubectl delete pod efa-test-prefill efa-test-decode

# Delete ETCD deployment
kubectl delete -f examples/etcd-deployment.yaml

# Verify cleanup
kubectl get pods -l app=efa-test
kubectl get pods -l app=etcd
```

================================================================================
## SUMMARY OF ALL POSSIBLE OUTCOMES
================================================================================

### Scenario 1: Everything Works (Expected)
- ETCD connectivity successful
- Both workers coordinate via ETCD
- Benchmark runs and completes
- Results show GPU-to-GPU bandwidth ~200-285 GB/s

### Scenario 2: ETCD Connection Fails
- Error: "Failed to acquire lock: the target uri is not valid"
- Fix: Update pod YAML with correct ETCD endpoint, redeploy

### Scenario 3: Worker Coordination Timeout
- Error: "Timeout waiting for workers"
- Fix: Launch both workers within 30 seconds, target first

### Scenario 4: UCX Device Not Found
- Error: "No UCX devices available"
- Fix: List devices with ucx_info -d, specify correct device

### Scenario 5: GPU Not Accessible
- Error: "CUDA error: no device found"
- Fix: Check GPU allocation in pod spec, verify nvidia-smi works

### Scenario 6: Pods Not Running
- Pods show "ImagePullBackOff" or "ErrImagePull"
- Fix: Check ECR authentication, verify image exists

================================================================================
## NEXT STEPS
================================================================================

After successful nixlbench run:

1. **Compare Results**: Compare nixlbench bandwidth vs ucx_perftest (284.98 GB/s)
2. **Test Different Backends**: Run tests with LIBFABRIC backend
3. **Test Different Memory Types**: Try DRAM-to-DRAM transfers
4. **Document Findings**: Update EFA_TEST_RESULTS.md with nixlbench metrics
5. **Production Deployment**: Use validated configuration for real workloads

================================================================================
# End of NIXL Benchmark Testing Guide
================================================================================
