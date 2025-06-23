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

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform first."
        exit 1
    fi
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    print_success "All prerequisites are satisfied."
}

# Check if terraform.tfvars exists
check_tfvars() {
    if [ ! -f "terraform.tfvars" ]; then
        print_warning "terraform.tfvars not found. Creating from example..."
        cp terraform.tfvars.example terraform.tfvars
        print_warning "Please edit terraform.tfvars with your specific values before proceeding."
        print_warning "Key values to update:"
        echo "  - cluster_endpoint_public_access_cidrs (your IP ranges)"
        echo "  - s3_mountpoint_bucket_name (your S3 bucket name)"
        echo "  - fsx_s3_import_path and fsx_s3_export_path (if using S3 integration)"
        read -p "Press Enter to continue after editing terraform.tfvars..."
    fi
}

# Initialize Terraform
init_terraform() {
    print_status "Initializing Terraform..."
    terraform init
    print_success "Terraform initialized successfully."
}

# Plan Terraform deployment
plan_terraform() {
    print_status "Planning Terraform deployment..."
    terraform plan -out=tfplan
    print_success "Terraform plan completed successfully."
}

# Apply Terraform configuration
apply_terraform() {
    print_status "Applying Terraform configuration..."
    print_warning "This will create AWS resources that may incur costs."
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform apply tfplan
        print_success "Terraform apply completed successfully."
    else
        print_status "Deployment cancelled."
        exit 0
    fi
}

# Configure kubectl
configure_kubectl() {
    print_status "Configuring kubectl..."
    
    # Get cluster name and region from Terraform outputs
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    REGION=$(terraform output -raw region)
    
    # Update kubeconfig
    aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME
    
    # Test connection
    if kubectl get nodes &> /dev/null; then
        print_success "kubectl configured successfully."
        print_status "Cluster nodes:"
        kubectl get nodes -o wide
    else
        print_error "Failed to connect to cluster. Please check your configuration."
        exit 1
    fi
}

# Deploy example workloads
deploy_examples() {
    print_status "Do you want to deploy example workloads?"
    read -p "Deploy examples? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deploying GPU workload example..."
        kubectl apply -f examples/gpu-workload.yaml
        
        print_status "Deploying FSx Lustre example..."
        kubectl apply -f examples/fsx-lustre-example.yaml
        
        print_status "Deploying S3 Mountpoint example..."
        kubectl apply -f examples/s3-mountpoint-example.yaml
        
        print_success "Example workloads deployed successfully."
        
        print_status "Checking deployment status..."
        kubectl get pods,pvc -o wide
    fi
}

# Display cluster information
show_cluster_info() {
    print_status "Cluster Information:"
    echo "===================="
    
    # Terraform outputs
    echo "Cluster Name: $(terraform output -raw cluster_name)"
    echo "Cluster Endpoint: $(terraform output -raw cluster_endpoint)"
    echo "Region: $(terraform output -raw region)"
    echo "VPC ID: $(terraform output -raw vpc_id)"
    
    echo ""
    print_status "Useful Commands:"
    echo "=================="
    echo "View cluster nodes: kubectl get nodes -o wide"
    echo "View all pods: kubectl get pods --all-namespaces"
    echo "View storage classes: kubectl get storageclass"
    echo "View persistent volumes: kubectl get pv,pvc --all-namespaces"
    echo "Check GPU nodes: kubectl describe nodes -l nvidia.com/gpu=true"
    echo "View cluster info: kubectl cluster-info"
    
    echo ""
    print_status "Monitoring:"
    echo "==========="
    echo "Check cluster autoscaler: kubectl logs -n kube-system -l app=cluster-autoscaler"
    echo "Check load balancer controller: kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller"
    echo "Check NVIDIA device plugin: kubectl logs -n kube-system -l name=nvidia-device-plugin-ds"
}

# Main deployment function
main() {
    print_status "Starting EKS Reference Architecture Deployment"
    echo "=============================================="
    
    check_prerequisites
    check_tfvars
    init_terraform
    plan_terraform
    apply_terraform
    configure_kubectl
    deploy_examples
    show_cluster_info
    
    print_success "Deployment completed successfully!"
    print_status "Your EKS cluster is ready to use."
    echo ""
    print_status "To destroy the infrastructure safely, use:"
    echo "  ./destroy.sh"
}

# Cleanup function
cleanup() {
    print_status "Starting cleanup process..."
    print_warning "This will destroy all resources created by Terraform."
    print_warning "Make sure to delete any Kubernetes resources (LoadBalancers, PVCs) first!"
    
    read -p "Are you sure you want to destroy all resources? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Delete example workloads first
        print_status "Deleting example workloads..."
        kubectl delete -f examples/ --ignore-not-found=true || true
        
        # Wait for cleanup
        print_status "Waiting for Kubernetes resources to be cleaned up..."
        sleep 30
        
        # Destroy Terraform resources
        print_status "Destroying Terraform resources..."
        terraform destroy -auto-approve
        
        print_success "Cleanup completed successfully."
    else
        print_status "Cleanup cancelled."
    fi
}

# Script usage
usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  deploy    - Deploy the EKS cluster (default)"
    echo "  cleanup   - Destroy all resources"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 deploy   # Deploy the cluster"
    echo "  $0 cleanup  # Destroy the cluster"
    echo "  $0          # Deploy the cluster (default)"
}

# Parse command line arguments
case "${1:-deploy}" in
    deploy)
        main
        ;;
    cleanup)
        cleanup
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        print_error "Unknown command: $1"
        usage
        exit 1
        ;;
esac