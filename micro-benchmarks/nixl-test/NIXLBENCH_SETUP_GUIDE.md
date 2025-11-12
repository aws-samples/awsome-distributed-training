# nixlbench Setup Guide - Based on Working Configuration

**Date:** November 10, 2025
**Status:** Setup guide based on successful friend configuration

This guide will help you replicate the working nixlbench setup that your friend achieved.

================================================================================
## PREREQUISITES
================================================================================

### 1. EKS Cluster Access

You need to authenticate with your EKS cluster:

```bash
# Set AWS credentials (get fresh credentials if expired)
export AWS_ACCESS_KEY_ID="YOUR_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="YOUR_SECRET_KEY"
export AWS_SESSION_TOKEN="YOUR_SESSION_TOKEN"  # if using temporary credentials

# Configure kubectl for EKS
aws eks update-kubeconfig --region us-east-2 --name sagemaker-hyperpod-eks-cluster

# Verify access
kubectl cluster-info
kubectl get nodes
```

### 2. Container Image

Your nixl-aligned:0.7.1-bench image should be available in ECR:
```
058264135704.dkr.ecr.us-east-2.amazonaws.com/nixl-aligned:0.7.1-bench
```

If not yet pushed, wait for the background push operations to complete (check logs with `tail -f push-nixl-aligned*.log`).

================================================================================
## STEP 1: DEPLOY ETCD SERVICE
================================================================================

### Create ETCD Deployment

Your friend's configuration uses `etcd.default:2379` which means ETCD is running in the `default` namespace with service name `etcd`.

Check if you have an ETCD deployment YAML. If not, create one:

```yaml
# File: /home/ubuntu/dynamo-workshop/examples/etcd-deployment.yaml

---
apiVersion: v1
kind: Service
metadata:
  name: etcd
  namespace: default
spec:
  type: ClusterIP
  ports:
  - name: client
    port: 2379
    targetPort: 2379
    protocol: TCP
  - name: peer
    port: 2380
    targetPort: 2380
    protocol: TCP
  selector:
    app: etcd

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: etcd
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: etcd
  template:
    metadata:
      labels:
        app: etcd
    spec:
      containers:
      - name: etcd
        image: quay.io/coreos/etcd:v3.5.18
        command:
        - /usr/local/bin/etcd
        - --name=etcd0
        - --listen-client-urls=http://0.0.0.0:2379
        - --advertise-client-urls=http://etcd:2379
        - --listen-peer-urls=http://0.0.0.0:2380
        - --initial-advertise-peer-urls=http://etcd:2380
        - --initial-cluster=etcd0=http://etcd:2380
        - --initial-cluster-token=etcd-cluster-1
        - --initial-cluster-state=new
        ports:
        - containerPort: 2379
          name: client
        - containerPort: 2380
          name: peer
        volumeMounts:
        - name: etcd-data
          mountPath: /var/lib/etcd
      volumes:
      - name: etcd-data
        emptyDir: {}
```

Deploy ETCD:

```bash
kubectl apply -f /home/ubuntu/dynamo-workshop/examples/etcd-deployment.yaml

# Wait for ETCD to be ready
kubectl wait --for=condition=ready pod -l app=etcd --timeout=60s

# Verify ETCD is running
kubectl get pods -l app=etcd
kubectl get svc etcd
```

Expected output:
```
NAME                    READY   STATUS    RESTARTS   AGE
etcd-xxxxxxxxxx-xxxxx   1/1     Running   0          30s

NAME   TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
etcd   ClusterIP   10.100.xxx.xxx   <none>        2379/TCP,2380/TCP   30s
```

================================================================================
## STEP 2: DEPLOY NIXLBENCH TEST PODS
================================================================================

### Create nixlbench Deployment

Based on your friend's configuration, they're using a Kubernetes Deployment (not individual Pods). This provides better management and can help with the rank assignment.

```yaml
# File: /home/ubuntu/dynamo-workshop/examples/nixl-benchmark-deployment.yaml

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nixl-benchmark
  namespace: default
spec:
  replicas: 2  # Two pods for initiator and target
  selector:
    matchLabels:
      app: nixl-benchmark
  template:
    metadata:
      labels:
        app: nixl-benchmark
    spec:
      hostNetwork: true
      hostIPC: true
      containers:
      - name: nixl-test
        image: 058264135704.dkr.ecr.us-east-2.amazonaws.com/nixl-aligned:0.7.1-bench
        command: ["/bin/bash", "-c", "sleep infinity"]
        env:
        - name: NIXL_ETCD_ENDPOINTS
          value: "http://etcd.default:2379"
        - name: NIXL_ETCD_NAMESPACE
          value: "/nixl/agents"
        - name: FI_PROVIDER
          value: "efa"
        - name: NCCL_DEBUG
          value: "INFO"
        resources:
          requests:
            nvidia.com/gpu: 8  # All 8 GPUs
            vpc.amazonaws.com/efa: 1
          limits:
            nvidia.com/gpu: 8
            vpc.amazonaws.com/efa: 1
        securityContext:
          privileged: true
          capabilities:
            add: ["IPC_LOCK", "SYS_ADMIN"]
        volumeMounts:
        - name: dev-infiniband
          mountPath: /dev/infiniband
        - name: sys
          mountPath: /sys
      volumes:
      - name: dev-infiniband
        hostPath:
          path: /dev/infiniband
      - name: sys
        hostPath:
          path: /sys
      # Anti-affinity to ensure pods run on different nodes
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - nixl-benchmark
            topologyKey: kubernetes.io/hostname
```

Deploy the nixlbench pods:

```bash
kubectl apply -f /home/ubuntu/dynamo-workshop/examples/nixl-benchmark-deployment.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=nixl-benchmark --timeout=120s

# Verify pods are running on different nodes
kubectl get pods -l app=nixl-benchmark -o wide
```

Expected output:
```
NAME                               READY   STATUS    RESTARTS   AGE   IP             NODE
nixl-benchmark-xxxxxxxxxx-xxxxx    1/1     Running   0          60s   10.1.xxx.xxx   hyperpod-i-xxxxxxxxxxxxx
nixl-benchmark-xxxxxxxxxx-yyyyy    1/1     Running   0          60s   10.1.yyy.yyy   hyperpod-i-yyyyyyyyyyy
```

**Important:** Verify the pods are on different nodes!

================================================================================
## STEP 3: TEST ETCD CONNECTIVITY
================================================================================

From within the pods, verify ETCD is accessible:

```bash
# Get pod names
POD1=$(kubectl get pods -l app=nixl-benchmark -o jsonpath='{.items[0].metadata.name}')
POD2=$(kubectl get pods -l app=nixl-benchmark -o jsonpath='{.items[1].metadata.name}')

echo "Pod 1: $POD1"
echo "Pod 2: $POD2"

# Test ETCD connectivity
kubectl exec -it $POD1 -- curl -s http://etcd.default:2379/version

# Expected output: {"etcdserver":"3.5.18","etcdcluster":"3.5.0"}
```

If you get a connection error, check:
1. ETCD pod is running: `kubectl get pods -l app=etcd`
2. Service exists: `kubectl get svc etcd`
3. DNS resolution works: `kubectl exec -it $POD1 -- nslookup etcd.default`

================================================================================
## STEP 4: RUN NIXLBENCH - UCX BACKEND
================================================================================

### Test Configuration (Based on Friend's Working Setup)

Run the benchmark on both pods. Open two terminals:

**Terminal 1 - Target Pod:**
```bash
POD1=$(kubectl get pods -l app=nixl-benchmark -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $POD1 -- bash -c '
nixlbench \
  -etcd_endpoints http://etcd.default:2379 \
  --backend UCX \
  --benchmark_group bg100000 \
  --target_seg_type VRAM \
  --initiator_seg_type VRAM \
  --num_initiator_dev=8 \
  --num_target_dev=8 \
  --total_buffer_size=64424509440 \
  --max_block_size=2147483648 \
  --mode=MG
'
```

**Terminal 2 - Initiator Pod (wait 5 seconds after Terminal 1):**
```bash
POD2=$(kubectl get pods -l app=nixl-benchmark -o jsonpath='{.items[1].metadata.name}')

kubectl exec -it $POD2 -- bash -c '
nixlbench \
  -etcd_endpoints http://etcd.default:2379 \
  --backend UCX \
  --benchmark_group bg100000 \
  --target_seg_type VRAM \
  --initiator_seg_type VRAM \
  --num_initiator_dev=8 \
  --num_target_dev=8 \
  --total_buffer_size=64424509440 \
  --max_block_size=2147483648 \
  --mode=MG
'
```

### Expected Output

**Target Pod (rank 1):**
```
WARNING: Adjusting num_iter to 1008 to allow equal distribution to 1 threads
WARNING: Adjusting warmup_iter to 112 to allow equal distribution to 1 threads
Connecting to ETCD at http://etcd.default:2379
ETCD Runtime: Registered as rank 1 item 2 of 2
Init nixl worker, dev all rank 1, type target, hostname nixl-benchmark-xxxxxxxxxx-xxxxx
[UCX protocol information...]
```

**Initiator Pod (rank 0):**
```
WARNING: Adjusting num_iter to 1008 to allow equal distribution to 1 threads
WARNING: Adjusting warmup_iter to 112 to allow equal distribution to 1 threads
Connecting to ETCD at http://etcd.default:2379
ETCD Runtime: Registered as rank 0 item 2 of 2
Init nixl worker, dev all rank 0, type initiator, hostname nixl-benchmark-xxxxxxxxxx-yyyyy
[Benchmark results...]
```

**SUCCESS INDICATORS:**
- ✅ "Registered as rank 0 item 2 of 2" and "Registered as rank 1 item 2 of 2"
- ✅ One pod as "initiator", other as "target"
- ✅ No barrier synchronization failures
- ✅ Benchmark runs and shows bandwidth/latency results

================================================================================
## STEP 5: RUN NIXLBENCH - LIBFABRIC BACKEND
================================================================================

Same as Step 4, but change `--backend UCX` to `--backend LIBFABRIC`:

**Terminal 1:**
```bash
kubectl exec -it $POD1 -- bash -c '
FI_LOG_LEVEL=info FI_LOG_PROV=efa nixlbench \
  -etcd_endpoints http://etcd.default:2379 \
  --backend LIBFABRIC \
  --benchmark_group bg100000 \
  --target_seg_type VRAM \
  --initiator_seg_type VRAM \
  --num_initiator_dev=8 \
  --num_target_dev=8 \
  --total_buffer_size=64424509440 \
  --max_block_size=2147483648 \
  --mode=MG
'
```

**Terminal 2 (after 5 seconds):**
```bash
kubectl exec -it $POD2 -- bash -c '
FI_LOG_LEVEL=info FI_LOG_PROV=efa nixlbench \
  -etcd_endpoints http://etcd.default:2379 \
  --backend LIBFABRIC \
  --benchmark_group bg100000 \
  --target_seg_type VRAM \
  --initiator_seg_type VRAM \
  --num_initiator_dev=8 \
  --num_target_dev=8 \
  --total_buffer_size=64424509440 \
  --max_block_size=2147483648 \
  --mode=MG
'
```

================================================================================
## TROUBLESHOOTING
================================================================================

### Issue: "Unauthorized" when running kubectl

**Solution:**
```bash
# Refresh AWS credentials
export AWS_ACCESS_KEY_ID="YOUR_NEW_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="YOUR_NEW_SECRET_KEY"
export AWS_SESSION_TOKEN="YOUR_NEW_SESSION_TOKEN"

# Reconfigure kubectl
aws eks update-kubeconfig --region us-east-2 --name sagemaker-hyperpod-eks-cluster

# Test
kubectl get nodes
```

### Issue: Both pods register as rank 0

**This is the race condition we documented.** Solutions:

1. **Use StatefulSet instead of Deployment:**
   - Edit deployment to use `kind: StatefulSet`
   - Add `podManagementPolicy: OrderedReady`
   - This ensures sequential pod startup

2. **Clear ETCD state before each test:**
```bash
# Get ETCD pod name
ETCD_POD=$(kubectl get pods -l app=etcd -o jsonpath='{.items[0].metadata.name}')

# Clear ETCD
kubectl exec $ETCD_POD -- etcdctl del "" --from-key=true

# Verify
kubectl exec $ETCD_POD -- etcdctl get "" --from-key=true
```

3. **Restart pods between tests:**
```bash
kubectl delete pods -l app=nixl-benchmark
kubectl wait --for=condition=ready pod -l app=nixl-benchmark --timeout=120s
```

### Issue: Connection refused or timeout

**Check ETCD status:**
```bash
kubectl get pods -l app=etcd
kubectl logs -l app=etcd
kubectl describe svc etcd
```

**Redeploy ETCD if needed:**
```bash
kubectl delete -f /home/ubuntu/dynamo-workshop/examples/etcd-deployment.yaml
kubectl apply -f /home/ubuntu/dynamo-workshop/examples/etcd-deployment.yaml
```

### Issue: Pods not finding GPUs

**Verify GPU allocation:**
```bash
kubectl exec -it $POD1 -- nvidia-smi

# Should show all 8 H100 GPUs
```

**Check resource requests:**
- Ensure `nvidia.com/gpu: 8` in pod spec
- Verify nodes have GPU resources: `kubectl describe node <node-name>`

================================================================================
## KEY DIFFERENCES FROM FRIEND'S CONFIG
================================================================================

Your friend's working setup uses:
1. ✅ ETCD endpoint: `http://etcd.default:2379` (not `etcd-service`)
2. ✅ Benchmark group: `bg100000`
3. ✅ 8 GPUs per pod: `--num_initiator_dev=8 --num_target_dev=8`
4. ✅ 60GB buffer: `--total_buffer_size=64424509440`
5. ✅ Up to 2GB blocks: `--max_block_size=2147483648`
6. ✅ Multi-GPU mode: `--mode=MG`

Make sure your configuration matches these exactly.

================================================================================
## QUICK START SCRIPT
================================================================================

Save this as `/home/ubuntu/dynamo-workshop/scripts/quick-start-nixlbench.sh`:

```bash
#!/bin/bash
set -e

echo "===== nixlbench Quick Start ====="
echo

# Step 1: Check cluster access
echo "Step 1: Checking cluster access..."
if ! kubectl cluster-info &>/dev/null; then
  echo "ERROR: Cannot access cluster. Please authenticate first:"
  echo "  export AWS_ACCESS_KEY_ID='...'"
  echo "  export AWS_SECRET_ACCESS_KEY='...'"
  echo "  export AWS_SESSION_TOKEN='...'"
  echo "  aws eks update-kubeconfig --region us-east-2 --name sagemaker-hyperpod-eks-cluster"
  exit 1
fi
echo "✅ Cluster access confirmed"
echo

# Step 2: Deploy ETCD
echo "Step 2: Deploying ETCD..."
kubectl apply -f examples/etcd-deployment.yaml
kubectl wait --for=condition=ready pod -l app=etcd --timeout=60s
echo "✅ ETCD deployed"
echo

# Step 3: Deploy nixlbench pods
echo "Step 3: Deploying nixlbench pods..."
kubectl apply -f examples/nixl-benchmark-deployment.yaml
kubectl wait --for=condition=ready pod -l app=nixl-benchmark --timeout=120s
echo "✅ nixlbench pods deployed"
echo

# Step 4: Verify setup
echo "Step 4: Verifying setup..."
kubectl get pods -l app=etcd -o wide
kubectl get pods -l app=nixl-benchmark -o wide
echo

# Step 5: Get pod names
POD1=$(kubectl get pods -l app=nixl-benchmark -o jsonpath='{.items[0].metadata.name}')
POD2=$(kubectl get pods -l app=nixl-benchmark -o jsonpath='{.items[1].metadata.name}')

echo "Pod 1 (Target): $POD1"
echo "Pod 2 (Initiator): $POD2"
echo

# Step 6: Test ETCD connectivity
echo "Step 6: Testing ETCD connectivity..."
kubectl exec -it $POD1 -- curl -s http://etcd.default:2379/version
echo "✅ ETCD connectivity confirmed"
echo

echo "===== Setup Complete! ====="
echo
echo "To run nixlbench, open TWO terminals and run:"
echo
echo "Terminal 1 (Target):"
echo "  kubectl exec -it $POD1 -- bash"
echo "  nixlbench -etcd_endpoints http://etcd.default:2379 --backend UCX --benchmark_group bg100000 --target_seg_type VRAM --initiator_seg_type VRAM --num_initiator_dev=8 --num_target_dev=8 --total_buffer_size=64424509440 --max_block_size=2147483648 --mode=MG"
echo
echo "Terminal 2 (Initiator) - Wait 5 seconds after Terminal 1:"
echo "  kubectl exec -it $POD2 -- bash"
echo "  nixlbench -etcd_endpoints http://etcd.default:2379 --backend UCX --benchmark_group bg100000 --target_seg_type VRAM --initiator_seg_type VRAM --num_initiator_dev=8 --num_target_dev=8 --total_buffer_size=64424509440 --max_block_size=2147483648 --mode=MG"
echo
```

Make it executable:
```bash
chmod +x /home/ubuntu/dynamo-workshop/scripts/quick-start-nixlbench.sh
```

Run it:
```bash
cd /home/ubuntu/dynamo-workshop
./scripts/quick-start-nixlbench.sh
```

================================================================================
## EXPECTED PERFORMANCE
================================================================================

Based on the UCX baseline of 284.98 GB/s, expect:

| Block Size | Bandwidth | Latency |
|------------|-----------|---------|
| 4 KB       | ~0.5 GB/s | ~0.008 ms |
| 64 KB      | ~8 GB/s   | ~0.010 ms |
| 1 MB       | ~120 GB/s | ~0.015 ms |
| 64 MB      | ~280 GB/s | ~0.230 ms |
| 2 GB       | ~280 GB/s | ~7-8 ms |

**Multi-GPU Aggregate:** With 8 GPUs per side, theoretical aggregate ~2.28 TB/s

================================================================================
## NEXT STEPS AFTER SUCCESS
================================================================================

1. **Save Results:**
   - Copy output to `/home/ubuntu/dynamo-experiment/nixlbench-results-$(date +%Y-%m-%d)/`
   - Create performance comparison charts

2. **Test Different Configurations:**
   - Different block sizes
   - Different buffer sizes
   - Different GPU counts
   - Compare UCX vs LIBFABRIC performance

3. **Scale Testing:**
   - Test with 4, 8, 16 nodes
   - Measure collective operations
   - Validate ETCD coordination at scale

================================================================================
END OF SETUP GUIDE
================================================================================
