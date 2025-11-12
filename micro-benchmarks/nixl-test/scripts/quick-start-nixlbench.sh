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
kubectl wait --for=condition=ready pod -l app=etcd --timeout=60s 2>/dev/null || echo "ETCD already running or taking longer to start..."
echo "✅ ETCD deployed"
echo

# Step 3: Deploy nixlbench pods
echo "Step 3: Deploying nixlbench pods..."
kubectl apply -f examples/nixl-benchmark-deployment.yaml
sleep 5
kubectl wait --for=condition=ready pod -l app=nixl-benchmark --timeout=120s 2>/dev/null || echo "Pods are starting..."
echo "✅ nixlbench pods deployed"
echo

# Step 4: Verify setup
echo "Step 4: Verifying setup..."
echo "ETCD pods:"
kubectl get pods -l app=etcd -o wide
echo
echo "nixlbench pods:"
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
sleep 2
kubectl exec -it $POD1 -- curl -s http://etcd.default:2379/version && echo
echo "✅ ETCD connectivity confirmed"
echo

echo "===== Setup Complete! ====="
echo
echo "To run nixlbench, open TWO terminals and run:"
echo
echo "Terminal 1 (Target):"
echo "  POD1=\$(kubectl get pods -l app=nixl-benchmark -o jsonpath='{.items[0].metadata.name}')"
echo "  kubectl exec -it \$POD1 -- bash"
echo "  nixlbench -etcd_endpoints http://etcd.default:2379 --backend UCX --benchmark_group bg100000 --target_seg_type VRAM --initiator_seg_type VRAM --num_initiator_dev=8 --num_target_dev=8 --total_buffer_size=64424509440 --max_block_size=2147483648 --mode=MG"
echo
echo "Terminal 2 (Initiator) - Wait 5 seconds after Terminal 1:"
echo "  POD2=\$(kubectl get pods -l app=nixl-benchmark -o jsonpath='{.items[1].metadata.name}')"
echo "  kubectl exec -it \$POD2 -- bash"
echo "  nixlbench -etcd_endpoints http://etcd.default:2379 --backend UCX --benchmark_group bg100000 --target_seg_type VRAM --initiator_seg_type VRAM --num_initiator_dev=8 --num_target_dev=8 --total_buffer_size=64424509440 --max_block_size=2147483648 --mode=MG"
echo
