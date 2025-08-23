#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available and connected
check_kubectl() {
    print_status "Checking kubectl connectivity..."
    if ! kubectl cluster-info &> /dev/null; then
        print_error "kubectl is not configured or cluster is not accessible."
        exit 1
    fi
    print_success "kubectl is configured and cluster is accessible."
}

# Check if Karpenter is installed
check_karpenter() {
    print_status "Checking if Karpenter is installed..."
    if kubectl get deployment -n karpenter karpenter &> /dev/null; then
        print_success "Karpenter is installed and running."
        kubectl get pods -n karpenter
    else
        print_error "Karpenter is not installed. Please deploy the cluster first."
        exit 1
    fi
}

# Check Karpenter NodePools and EC2NodeClasses
check_karpenter_resources() {
    print_status "Checking Karpenter NodePools..."
    kubectl get nodepool
    
    print_status "Checking Karpenter EC2NodeClasses..."
    kubectl get ec2nodeclass
    
    print_status "Checking current nodes..."
    kubectl get nodes -o wide
}

# Deploy test workloads
deploy_workloads() {
    print_status "Deploying Karpenter test workloads..."
    kubectl apply -f karpenter-workloads.yaml
    
    print_status "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/karpenter-example-app
    kubectl wait --for=condition=available --timeout=300s deployment/karpenter-mixed-workload
    
    print_success "Test workloads deployed successfully."
}

# Test Karpenter scaling
test_scaling() {
    print_status "Testing Karpenter node provisioning..."
    
    # Get initial node count
    INITIAL_NODES=$(kubectl get nodes --no-headers | wc -l)
    print_status "Initial node count: $INITIAL_NODES"
    
    # Scale up the burst workload to trigger node provisioning
    print_status "Scaling up burst workload to trigger node provisioning..."
    kubectl scale deployment karpenter-burst-workload --replicas=10
    
    # Wait for Karpenter to provision new nodes
    print_status "Waiting for Karpenter to provision new nodes (this may take 2-3 minutes)..."
    
    for i in {1..18}; do  # Wait up to 3 minutes
        CURRENT_NODES=$(kubectl get nodes --no-headers | wc -l)
        if [ $CURRENT_NODES -gt $INITIAL_NODES ]; then
            print_success "Karpenter provisioned new nodes! Current count: $CURRENT_NODES"
            break
        fi
        echo "Waiting... ($i/18) Current nodes: $CURRENT_NODES"
        sleep 10
    done
    
    # Show new nodes
    print_status "Current node status:"
    kubectl get nodes -o wide
    
    # Show Karpenter logs
    print_status "Recent Karpenter logs:"
    kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=20
}

# Test GPU workload (if GPU nodes are available)
test_gpu_workload() {
    print_status "Testing GPU workload..."
    
    # Check if GPU NodePool exists
    if kubectl get nodepool gpu &> /dev/null; then
        print_status "GPU NodePool found. Deploying GPU workload..."
        kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: karpenter-gpu-test
  namespace: default
spec:
  template:
    spec:
      containers:
      - name: gpu-test
        image: nvidia/cuda:11.8-base-ubuntu20.04
        command: ["nvidia-smi"]
        resources:
          requests:
            nvidia.com/gpu: 1
          limits:
            nvidia.com/gpu: 1
      nodeSelector:
        node-type: gpu
      tolerations:
      - key: nvidia.com/gpu
        effect: NoSchedule
      restartPolicy: Never
  backoffLimit: 1
EOF
        
        print_status "Waiting for GPU job to complete..."
        kubectl wait --for=condition=complete --timeout=600s job/karpenter-gpu-test
        
        print_status "GPU job logs:"
        kubectl logs job/karpenter-gpu-test
        
        print_success "GPU workload test completed."
    else
        print_warning "GPU NodePool not found. Skipping GPU test."
    fi
}

# Test spot instance interruption handling
test_spot_handling() {
    print_status "Testing spot instance handling..."
    
    # Check if there are any spot instances
    SPOT_NODES=$(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ $SPOT_NODES -gt 0 ]; then
        print_success "Found $SPOT_NODES spot instance(s)."
        kubectl get nodes -l karpenter.sh/capacity-type=spot -o wide
        
        print_status "Karpenter should handle spot interruptions automatically."
        print_status "Check SQS queue for interruption messages: $(kubectl get nodepool default -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "N/A")"
    else
        print_warning "No spot instances found. Karpenter may not have provisioned spot instances yet."
    fi
}

# Monitor Karpenter metrics
monitor_karpenter() {
    print_status "Monitoring Karpenter status..."
    
    # Show NodePool status
    print_status "NodePool status:"
    kubectl get nodepool -o wide
    
    # Show node capacity and usage
    print_status "Node resource usage:"
    kubectl top nodes 2>/dev/null || print_warning "Metrics server not available"
    
    # Show pod distribution
    print_status "Pod distribution across nodes:"
    kubectl get pods -o wide | grep -E "(karpenter|gpu|burst|mixed)" | head -10
    
    # Show Karpenter events
    print_status "Recent Karpenter events:"
    kubectl get events --field-selector involvedObject.kind=Node --sort-by='.lastTimestamp' | tail -10
}

# Scale down test
test_scale_down() {
    print_status "Testing Karpenter scale-down behavior..."
    
    # Scale down workloads
    print_status "Scaling down workloads..."
    kubectl scale deployment karpenter-burst-workload --replicas=1
    kubectl scale deployment karpenter-mixed-workload --replicas=2
    
    print_status "Workloads scaled down. Karpenter should consolidate or terminate unused nodes."
    print_status "This process may take several minutes. Monitor with: kubectl get nodes -w"
    
    CURRENT_NODES=$(kubectl get nodes --no-headers | wc -l)
    print_status "Current node count: $CURRENT_NODES"
    print_status "Karpenter will evaluate nodes for termination based on the consolidation policy."
}

# Cleanup function
cleanup() {
    print_status "Cleaning up test resources..."
    kubectl delete -f karpenter-workloads.yaml --ignore-not-found=true
    kubectl delete job karpenter-gpu-test --ignore-not-found=true
    print_success "Cleanup completed."
}

# Show help
show_help() {
    echo "Karpenter Test Script"
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  deploy      Deploy test workloads"
    echo "  test        Run comprehensive Karpenter tests"
    echo "  scale       Test scaling behavior"
    echo "  gpu         Test GPU workload"
    echo "  monitor     Monitor Karpenter status"
    echo "  cleanup     Remove test workloads"
    echo "  help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 test     # Run full test suite"
    echo "  $0 deploy   # Just deploy workloads"
    echo "  $0 monitor  # Monitor current status"
}

# Main function
main() {
    case "${1:-test}" in
        deploy)
            check_kubectl
            check_karpenter
            deploy_workloads
            ;;
        test)
            check_kubectl
            check_karpenter
            check_karpenter_resources
            deploy_workloads
            test_scaling
            test_gpu_workload
            test_spot_handling
            monitor_karpenter
            test_scale_down
            ;;
        scale)
            check_kubectl
            check_karpenter
            test_scaling
            ;;
        gpu)
            check_kubectl
            check_karpenter
            test_gpu_workload
            ;;
        monitor)
            check_kubectl
            check_karpenter
            monitor_karpenter
            ;;
        cleanup)
            check_kubectl
            cleanup
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Handle script interruption
trap cleanup EXIT

# Run main function
main "$@"