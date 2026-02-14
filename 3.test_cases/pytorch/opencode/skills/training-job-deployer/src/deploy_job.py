#!/usr/bin/env python3
"""
Training Job Deployer Skill
Deploy and manage training jobs on EKS with monitoring and auto-retry.
Supports both PyTorchJob (torchrun) and Ray (KubeRay) for distributed training.
"""

import argparse
import sys
import os
import json
import subprocess

# Add shared utilities to path
sys.path.insert(0, os.path.expanduser('~/.opencode/skills/shared'))

from job_deployer import JobDeployer
from failure_analyzer import FailureAnalyzer
from logger import create_logger


def check_ray_installed(cluster_name: str) -> bool:
    """Check if KubeRay operator is installed on the cluster."""
    try:
        # Check for RayCluster CRD
        result = subprocess.run(
            ['kubectl', 'get', 'crd', 'rayclusters.ray.io'],
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.returncode == 0
    except Exception:
        return False


def install_kuberay(cluster_name: str, region: str = "us-west-2") -> bool:
    """Install KubeRay operator on the cluster."""
    logger = create_logger('training-job-deployer')
    logger.info("📦 Installing KubeRay operator...")
    
    try:
        # Add KubeRay Helm repo
        result = subprocess.run(
            ['helm', 'repo', 'add', 'kuberay', 'https://ray-project.github.io/kuberay-helm/'],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        # Update Helm repos
        subprocess.run(
            ['helm', 'repo', 'update'],
            capture_output=True,
            timeout=30
        )
        
        # Install KubeRay operator
        result = subprocess.run(
            [
                'helm', 'install', 'kuberay-operator', 'kuberay/kuberay-operator',
                '--namespace', 'kuberay',
                '--create-namespace',
                '--version', '1.1.0'
            ],
            capture_output=True,
            text=True,
            timeout=60
        )
        
        if result.returncode == 0:
            logger.success("✅ KubeRay operator installed successfully")
            # Wait for operator to be ready
            logger.info("⏳ Waiting for KubeRay operator to be ready...")
            subprocess.run(
                ['kubectl', 'wait', '--for=condition=ready', 'pod', 
                 '-l', 'app.kubernetes.io/name=kuberay-operator', 
                 '-n', 'kuberay', '--timeout=120s'],
                capture_output=True,
                timeout=130
            )
            return True
        else:
            logger.error(f"❌ Failed to install KubeRay: {result.stderr}")
            return False
            
    except Exception as e:
        logger.error(f"❌ Error installing KubeRay: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description='Deploy distributed training job on EKS using torchrun or Ray'
    )
    parser.add_argument('--job_name', default='fsdp-training', help='Job name')
    parser.add_argument('--image_uri', default='', help='Docker image URI (auto-detect from ECR if empty)')
    parser.add_argument('--instance_type', default='ml.g5.8xlarge', help='EC2 instance type')
    parser.add_argument('--num_nodes', type=int, default=4, help='Number of nodes for distributed training')
    parser.add_argument('--gpu_per_node', type=int, default=1, help='Number of GPUs per node')
    parser.add_argument('--cluster_name', default='', help='EKS cluster name (required)')
    parser.add_argument('--torchrun_path', default='/opt/conda/bin/torchrun', 
                       help='Path to torchrun in container')
    parser.add_argument('--use_hyperpod_cli', default='auto', 
                       help='Use HyperPod CLI: auto, true, or false')
    parser.add_argument('--use_ray', action='store_true',
                       help='Use Ray (KubeRay) instead of PyTorchJob for distributed training')
    parser.add_argument('--ray_address', default='auto',
                       help='Ray cluster address (default: auto)')
    parser.add_argument('--install_ray', action='store_true',
                       help='Install KubeRay operator if not present')
    parser.add_argument('--monitor', type=lambda x: x.lower() == 'true',
                       default=True, help='Monitor job after deployment')
    parser.add_argument('--auto_retry', type=lambda x: x.lower() == 'true',
                       default=True, help='Auto-retry on known failures')
    parser.add_argument('--save_config', type=lambda x: x.lower() == 'true',
                       default=True, help='Save config to ConfigMap')
    parser.add_argument('--hf_token', default='', help='HuggingFace token for gated models')
    parser.add_argument('--sns_topic', default='', help='SNS topic ARN for notifications')
    
    args = parser.parse_args()
    
    logger = create_logger('training-job-deployer')
    
    if not args.cluster_name:
        logger.error("Cluster name required. Use --cluster_name")
        return 1
    
    # Check and install Ray if requested
    if args.use_ray or args.install_ray:
        if not check_ray_installed(args.cluster_name):
            logger.warning("⚠️  KubeRay operator not found on cluster")
            if args.install_ray:
                if not install_kuberay(args.cluster_name):
                    logger.error("Failed to install KubeRay. Exiting.")
                    return 1
            else:
                logger.error("Use --install_ray to install KubeRay operator")
                return 1
        else:
            logger.success("✅ KubeRay operator is installed")
    
    # Initialize deployer
    deployer = JobDeployer(
        cluster_name=args.cluster_name,
        verbose=True
    )
    
    # Verify image
    image_uri = args.image_uri
    if not image_uri:
        # Auto-detect from ECR
        logger.info("Auto-detecting image from ECR...")
        image_uri = f"975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest"
    
    success, message = deployer.verify_image(image_uri)
    if not success:
        logger.warning(f"Image verification: {message}")
    else:
        logger.success(f"Image verified: {image_uri}")
    
    # Build job config
    job_config = {
        'job_name': args.job_name,
        'image_uri': image_uri,
        'instance_type': args.instance_type,
        'num_nodes': args.num_nodes,
        'gpu_per_node': args.gpu_per_node,
        'efa_per_node': 1,
        'cluster_name': args.cluster_name,
        'torchrun_path': args.torchrun_path,
        'model_type': 'llama_v3',
        'max_steps': 100,
        'hf_token': args.hf_token if args.hf_token else None,
        'tokenizer': 'hf-internal-testing/llama-tokenizer',
        'dataset': 'allenai/c4',
        'dataset_config_name': 'en',
        'sharding_strategy': 'full',
        'checkpoint_dir': '/checkpoints',
        'use_ray': args.use_ray,
        'ray_address': args.ray_address
    }
    
    # Generate manifest
    logger.info("Generating Kubernetes manifest...")
    
    if args.use_ray:
        logger.info("🎯 Using Ray (KubeRay) for distributed training")
        manifest = deployer.generate_ray_manifest(job_config)
        deployment_method = 'ray'
    else:
        use_hyperpod = args.use_hyperpod_cli == 'true' or (args.use_hyperpod_cli == 'auto' and deployer._detect_deployment_method() == 'hyperpod-cli')
        format_type = 'hyperpod-cli' if use_hyperpod else 'kubectl'
        manifest = deployer.generate_manifest(job_config, format=format_type)
        deployment_method = args.use_hyperpod_cli
    
    # Show preview
    print("\n" + "="*80)
    print("Job Configuration Preview")
    print("="*80)
    print(f"Name: {job_config['job_name']}")
    print(f"Image: {job_config['image_uri']}")
    print(f"Nodes: {job_config['num_nodes']} x {job_config['instance_type']}")
    print(f"GPUs: {job_config['num_nodes']} nodes x {job_config['gpu_per_node']} GPUs = {job_config['num_nodes'] * job_config['gpu_per_node']} total GPUs")
    if args.use_ray:
        print(f"Framework: Ray (KubeRay)")
        print(f"Ray Address: {job_config['ray_address']}")
    else:
        print(f"Framework: PyTorchJob (torchrun)")
        print(f"Torchrun: {job_config['torchrun_path']}")
    print(f"Format: {deployment_method}")
    print("="*80)
    
    # Deploy
    logger.info(f"🚀 Deploying job...")
    success, output = deployer.deploy_job(manifest, method=deployment_method)
    
    if not success:
        logger.error(f"Deployment failed: {output}")
        return 1
    
    logger.success(f"✅ Job deployed: {args.job_name}")
    
    # Monitor
    if args.monitor:
        logger.info("📊 Starting job monitoring...")
        if args.use_ray:
            deployer.monitor_ray_job(args.job_name, mode='hybrid')
        else:
            deployer.monitor_job(args.job_name, mode='hybrid')
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
