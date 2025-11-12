# kubectl Quick Reference - NIXL Benchmark Testing

**COPY AND PASTE THESE COMMANDS DIRECTLY INTO YOUR KUBECTL TERMINAL**

================================================================================
## STEP 1: VERIFY EVERYTHING IS READY
================================================================================

```bash
# Check cluster connection
kubectl cluster-info

# Check ETCD service
kubectl get svc etcd-service

# Check test pods
kubectl get pods -l app=efa-test -o wide

# Expected: Both pods Running on different nodes
```

================================================================================
## STEP 2: VERIFY NIXLBENCH IS INSTALLED
================================================================================

```bash
# Check nixlbench exists
kubectl exec -it efa-test-prefill -- which nixlbench

# Expected output: /usr/local/bin/nixlbench
```

================================================================================
## STEP 3: TEST ETCD CONNECTIVITY  
================================================================================

```bash
# Test from prefill pod
kubectl exec -it efa-test-prefill -- curl -s http://etcd-service:2379/version

# Expected: {"etcdserver":"3.5.18","etcdcluster":"3.5.0"}
```

================================================================================
## STEP 4: RUN NIXLBENCH (CHOOSE ONE METHOD)
================================================================================

### METHOD A: TWO SEPARATE TERMINALS (RECOMMENDED)

**Open Terminal 1** and run:
```bash
kubectl exec -it efa-test-decode -- bash -c 'nixlbench --etcd_endpoints http://etcd-service:2379 --backend UCX --initiator_seg_type VRAM --target_seg_type VRAM --start_block_size 4096 --max_block_size 67108864 --num_iter 1000 --warmup_iter 100'
```

Wait 5 seconds, then **Open Terminal 2** and run:
```bash
kubectl exec -it efa-test-prefill -- bash -c 'nixlbench --etcd_endpoints http://etcd-service:2379 --backend UCX --initiator_seg_type VRAM --target_seg_type VRAM --start_block_size 4096 --max_block_size 67108864 --num_iter 1000 --warmup_iter 100'
```

### METHOD B: BACKGROUND + FOREGROUND (SINGLE TERMINAL)

```bash
# Start target in background
kubectl exec -d efa-test-decode -- bash -c 'nixlbench --etcd_endpoints http://etcd-service:2379 --backend UCX --initiator_seg_type VRAM --target_seg_type VRAM --start_block_size 4096 --max_block_size 67108864 --num_iter 1000 --warmup_iter 100 > /tmp/nixlbench-decode.log 2>&1'

# Wait 10 seconds
sleep 10

# Start initiator in foreground (you'll see output)
kubectl exec -it efa-test-prefill -- bash -c 'nixlbench --etcd_endpoints http://etcd-service:2379 --backend UCX --initiator_seg_type VRAM --target_seg_type VRAM --start_block_size 4096 --max_block_size 67108864 --num_iter 1000 --warmup_iter 100'

# Check decode pod logs
kubectl exec -it efa-test-decode -- cat /tmp/nixlbench-decode.log
```

================================================================================
## TROUBLESHOOTING COMMANDS
================================================================================

### If Error: "target uri is not valid"

```bash
# Check environment variables
kubectl exec -it efa-test-prefill -- env | grep ETCD

# Should show:
# NIXL_ETCD_ENDPOINTS=http://etcd-service:2379
# NIXL_ETCD_NAMESPACE=/nixl/agents

# If missing, redeploy pods
kubectl delete pod efa-test-prefill efa-test-decode
kubectl apply -f /home/ubuntu/dynamo-workshop/examples/efa-test-pods.yaml
```

### If ETCD Not Responding

```bash
# Restart ETCD
kubectl delete pod -l app=etcd
kubectl get pods -l app=etcd -w

# Test again
kubectl exec -it efa-test-prefill -- curl http://etcd-service:2379/version
```

### List Available UCX Devices

```bash
kubectl exec -it efa-test-prefill -- ucx_info -d
```

### Check GPU Status

```bash
kubectl exec -it efa-test-prefill -- nvidia-smi
```

### Interactive Debug Shell

```bash
# Prefill pod
kubectl exec -it efa-test-prefill -- bash

# Decode pod  
kubectl exec -it efa-test-decode -- bash
```

================================================================================
## EXPECTED RESULTS
================================================================================

You should see output like:

```
Connecting to ETCD at http://etcd-service:2379
Successfully connected to ETCD
Worker coordination successful (2 workers)
Starting benchmark with UCX backend...

Block Size: 4096 bytes
  Bandwidth: 0.52 GB/s
  Latency: 0.008 ms
  
Block Size: 8192 bytes
  Bandwidth: 1.04 GB/s
  Latency: 0.008 ms
  
...

Block Size: 67108864 bytes (64 MB)
  Bandwidth: 283.45 GB/s
  Latency: 0.237 ms

Benchmark complete!
```

Target bandwidth for large blocks: **280-285 GB/s** (similar to UCX perftest: 284.98 GB/s)

================================================================================
## ALL POSSIBLE SCENARIOS
================================================================================

### ✅ SUCCESS
- Both workers connect to ETCD
- Coordination succeeds  
- Benchmark runs and completes
- Bandwidth ~200-285 GB/s for large blocks

### ⚠️ ETCD URI ERROR
Error: "Failed to acquire lock: the target uri is not valid"
Fix: Redeploy pods with correct ETCD configuration

### ⚠️ TIMEOUT
Error: "Timeout waiting for workers"
Fix: Launch both workers within 30 seconds, decode first

### ⚠️ NO DEVICE
Error: "UCX device not found"
Fix: Run `ucx_info -d` to list devices, specify with --device_list

### ⚠️ NO GPU
Error: "CUDA error: no device found"
Fix: Check pod GPU allocation, verify nvidia-smi works

### ⚠️ IMAGE PULL ERROR
Pods stuck in "ImagePullBackOff"
Fix: Check ECR authentication, verify image exists

================================================================================
## CLEANUP
================================================================================

```bash
# Delete test pods
kubectl delete pod efa-test-prefill efa-test-decode

# Delete ETCD
kubectl delete -f /home/ubuntu/dynamo-workshop/examples/etcd-deployment.yaml
```

================================================================================
# End of Quick Reference
================================================================================
