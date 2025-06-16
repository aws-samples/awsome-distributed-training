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

# Function to check if kubectl is configured
check_kubectl() {
    print_status "Checking kubectl configuration..."
    if ! kubectl cluster-info &> /dev/null; then
        print_warning "kubectl is not configured or cluster is not accessible."
        print_warning "Some cleanup steps will be skipped."
        return 1
    fi
    print_success "kubectl is configured and cluster is accessible."
    return 0
}

# Function to get cluster name from terraform output
get_cluster_name() {
    if [ -f "terraform.tfstate" ]; then
        CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
        if [ -n "$CLUSTER_NAME" ]; then
            print_status "Found cluster name from Terraform: $CLUSTER_NAME"
            return 0
        fi
    fi
    
    # Try to get from kubectl context
    CLUSTER_NAME=$(kubectl config current-context 2>/dev/null | grep -o 'arn:aws:eks:[^:]*:[^:]*:cluster/[^/]*' | cut -d'/' -f2 2>/dev/null || echo "")
    if [ -n "$CLUSTER_NAME" ]; then
        print_status "Found cluster name from kubectl context: $CLUSTER_NAME"
        return 0
    fi
    
    print_warning "Could not determine cluster name"
    return 1
}

# Function to delete LoadBalancer services
delete_load_balancers() {
    print_status "Checking for LoadBalancer services..."
    
    LB_SERVICES=$(kubectl get svc --all-namespaces -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "")
    
    if [ -n "$LB_SERVICES" ]; then
        print_warning "Found LoadBalancer services that need to be deleted:"
        echo "$LB_SERVICES"
        
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                NAMESPACE=$(echo "$line" | awk '{print $1}')
                SERVICE=$(echo "$line" | awk '{print $2}')
                print_status "Deleting LoadBalancer service: $NAMESPACE/$SERVICE"
                kubectl delete svc "$SERVICE" -n "$NAMESPACE" --timeout=300s || print_warning "Failed to delete service $NAMESPACE/$SERVICE"
            fi
        done <<< "$LB_SERVICES"
        
        print_status "Waiting for LoadBalancers to be fully deleted..."
        sleep 30
    else
        print_success "No LoadBalancer services found."
    fi
}

# Function to delete Ingress resources
delete_ingresses() {
    print_status "Checking for Ingress resources..."
    
    INGRESSES=$(kubectl get ingress --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "")
    
    if [ -n "$INGRESSES" ]; then
        print_warning "Found Ingress resources that need to be deleted:"
        echo "$INGRESSES"
        
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                NAMESPACE=$(echo "$line" | awk '{print $1}')
                INGRESS=$(echo "$line" | awk '{print $2}')
                print_status "Deleting Ingress: $NAMESPACE/$INGRESS"
                kubectl delete ingress "$INGRESS" -n "$NAMESPACE" --timeout=300s || print_warning "Failed to delete ingress $NAMESPACE/$INGRESS"
            fi
        done <<< "$INGRESSES"
        
        print_status "Waiting for Ingresses to be fully deleted..."
        sleep 30
    else
        print_success "No Ingress resources found."
    fi
}

# Function to delete PersistentVolumeClaims
delete_pvcs() {
    print_status "Checking for PersistentVolumeClaims..."
    
    PVCS=$(kubectl get pvc --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "")
    
    if [ -n "$PVCS" ]; then
        print_warning "Found PersistentVolumeClaims that need to be deleted:"
        echo "$PVCS"
        
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                NAMESPACE=$(echo "$line" | awk '{print $1}')
                PVC=$(echo "$line" | awk '{print $2}')
                print_status "Deleting PVC: $NAMESPACE/$PVC"
                kubectl delete pvc "$PVC" -n "$NAMESPACE" --timeout=300s || print_warning "Failed to delete PVC $NAMESPACE/$PVC"
            fi
        done <<< "$PVCS"
        
        print_status "Waiting for PVCs to be fully deleted..."
        sleep 30
    else
        print_success "No PersistentVolumeClaims found."
    fi
}

# Function to delete example workloads
delete_example_workloads() {
    print_status "Deleting example workloads..."
    
    if [ -d "examples" ]; then
        for example_file in examples/*.yaml; do
            if [ -f "$example_file" ]; then
                print_status "Deleting resources from $example_file"
                kubectl delete -f "$example_file" --ignore-not-found=true --timeout=300s || print_warning "Failed to delete some resources from $example_file"
            fi
        done
        print_success "Example workloads cleanup completed."
    else
        print_status "No examples directory found."
    fi
}

# Function to delete AWS Load Balancer Controller resources
delete_alb_resources() {
    print_status "Checking for AWS Load Balancer Controller managed resources..."
    
    # Delete TargetGroupBinding resources
    TGB_RESOURCES=$(kubectl get targetgroupbindings --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "")
    
    if [ -n "$TGB_RESOURCES" ]; then
        print_warning "Found TargetGroupBinding resources:"
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                NAMESPACE=$(echo "$line" | awk '{print $1}')
                TGB=$(echo "$line" | awk '{print $2}')
                print_status "Deleting TargetGroupBinding: $NAMESPACE/$TGB"
                kubectl delete targetgroupbinding "$TGB" -n "$NAMESPACE" --timeout=300s || print_warning "Failed to delete TargetGroupBinding $NAMESPACE/$TGB"
            fi
        done <<< "$TGB_RESOURCES"
    fi
    
    print_success "AWS Load Balancer Controller resources cleanup completed."
}

# Function to wait for all resources to be deleted
wait_for_cleanup() {
    print_status "Waiting for all Kubernetes resources to be fully cleaned up..."
    
    # Wait up to 10 minutes for resources to be deleted
    for i in {1..60}; do
        LB_COUNT=$(kubectl get svc --all-namespaces -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | wc -l || echo "0")
        PVC_COUNT=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
        INGRESS_COUNT=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [ "$LB_COUNT" -eq 0 ] && [ "$PVC_COUNT" -eq 0 ] && [ "$INGRESS_COUNT" -eq 0 ]; then
            print_success "All Kubernetes resources have been cleaned up."
            break
        fi
        
        print_status "Still waiting for cleanup... (${i}/60) - LBs: $LB_COUNT, PVCs: $PVC_COUNT, Ingresses: $INGRESS_COUNT"
        sleep 10
    done
}

# Function to check for remaining AWS resources
check_aws_resources() {
    print_status "Checking for remaining AWS resources that might block Terraform destroy..."
    
    if command -v aws &> /dev/null && [ -n "$CLUSTER_NAME" ]; then
        print_status "Checking for remaining Load Balancers..."
        aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, '$CLUSTER_NAME')].LoadBalancerName" --output table 2>/dev/null || print_warning "Could not check ELBv2 resources"
        
        print_status "Checking for remaining Security Groups..."
        aws ec2 describe-security-groups --filters "Name=group-name,Values=*$CLUSTER_NAME*" --query "SecurityGroups[].GroupName" --output table 2>/dev/null || print_warning "Could not check Security Groups"
        
        print_status "Checking for remaining Target Groups..."
        aws elbv2 describe-target-groups --query "TargetGroups[?contains(TargetGroupName, '$CLUSTER_NAME')].TargetGroupName" --output table 2>/dev/null || print_warning "Could not check Target Groups"
    else
        print_warning "AWS CLI not available or cluster name not found. Skipping AWS resource check."
    fi
}

# Function to run terraform destroy
run_terraform_destroy() {
    print_status "Running terraform destroy..."
    print_warning "This will destroy all Terraform-managed infrastructure."
    print_warning "Make sure you have backed up any important data."
    
    read -p "Are you sure you want to proceed with terraform destroy? (yes/no): " -r
    if [[ $REPLY == "yes" ]]; then
        print_status "Proceeding with terraform destroy..."
        
        # Initialize terraform if needed
        if [ ! -d ".terraform" ]; then
            print_status "Initializing Terraform..."
            terraform init
        fi
        
        # Run destroy with auto-approve
        terraform destroy -auto-approve
        
        if [ $? -eq 0 ]; then
            print_success "Terraform destroy completed successfully!"
        else
            print_error "Terraform destroy failed. Please check the output above."
            exit 1
        fi
    else
        print_status "Terraform destroy cancelled."
        exit 0
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    print_status "Cleaning up local files..."
    
    # Remove terraform state backup files
    rm -f terraform.tfstate.backup* 2>/dev/null || true
    rm -f tfplan* 2>/dev/null || true
    
    # Remove kubectl config backups
    rm -f kubeconfig* 2>/dev/null || true
    
    print_success "Local cleanup completed."
}

# Main function
main() {
    print_status "Starting EKS Infrastructure Destruction"
    echo "========================================"
    
    print_warning "This script will:"
    echo "1. Delete all Kubernetes resources that create AWS resources"
    echo "2. Wait for cleanup to complete"
    echo "3. Run terraform destroy to remove all infrastructure"
    echo "4. Clean up local files"
    echo ""
    
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Destruction cancelled."
        exit 0
    fi
    
    # Check prerequisites
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed."
        exit 1
    fi
    
    # Get cluster name
    get_cluster_name
    
    # Check kubectl and proceed with Kubernetes cleanup if available
    if check_kubectl; then
        print_status "Starting Kubernetes resource cleanup..."
        
        delete_example_workloads
        delete_load_balancers
        delete_ingresses
        delete_alb_resources
        delete_pvcs
        wait_for_cleanup
        
        print_success "Kubernetes cleanup completed."
    else
        print_warning "Skipping Kubernetes cleanup due to connectivity issues."
        print_warning "You may need to manually clean up AWS resources if Terraform destroy fails."
    fi
    
    # Check for remaining AWS resources
    check_aws_resources
    
    # Wait a bit more to ensure AWS resources are cleaned up
    print_status "Waiting additional 60 seconds for AWS resource cleanup..."
    sleep 60
    
    # Run terraform destroy
    run_terraform_destroy
    
    # Clean up local files
    cleanup_local_files
    
    print_success "Infrastructure destruction completed!"
    print_status "All resources have been destroyed and local files cleaned up."
}

# Handle script termination
cleanup_on_exit() {
    print_warning "Script interrupted. Some resources may not be fully cleaned up."
    print_warning "You may need to manually delete remaining AWS resources."
}

trap cleanup_on_exit EXIT

# Help function
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --skip-k8s-cleanup    Skip Kubernetes resource cleanup"
    echo "  --force              Skip confirmation prompts"
    echo "  --help               Show this help message"
    echo ""
    echo "This script safely destroys the EKS infrastructure by:"
    echo "1. Cleaning up Kubernetes resources that create AWS resources"
    echo "2. Waiting for AWS resources to be fully deleted"
    echo "3. Running terraform destroy"
    echo "4. Cleaning up local files"
}

# Parse command line arguments
SKIP_K8S_CLEANUP=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-k8s-cleanup)
            SKIP_K8S_CLEANUP=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Override main function for options
if [ "$SKIP_K8S_CLEANUP" = true ]; then
    print_warning "Skipping Kubernetes cleanup as requested."
    run_terraform_destroy
    cleanup_local_files
    exit 0
fi

if [ "$FORCE" = true ]; then
    print_warning "Force mode enabled. Skipping confirmations."
    # Override read commands in functions
    export REPLY="yes"
fi

# Run main function
main