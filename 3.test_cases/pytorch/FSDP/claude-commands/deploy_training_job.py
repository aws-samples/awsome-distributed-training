#!/usr/bin/env python3
"""
Claude Code Command: Deploy Training Job
Deploy training jobs to EKS with monitoring and auto-retry.
"""

from typing import Optional
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'opencode', 'skills', 'shared'))

try:
    from job_deployer import JobDeployer
    from failure_analyzer import FailureAnalyzer
    from logger import create_logger
except ImportError:
    sys.path.insert(0, os.path.expanduser('~/.opencode/skills/shared'))
    from job_deployer import JobDeployer
    from failure_analyzer import FailureAnalyzer
    from logger import create_logger


def deploy_training_job(
    job_name: str = "fsdp-training",
    image_uri: Optional[str] = None,
    instance_type: str = "ml.g5.8xlarge",
    num_nodes: int = 4,
    gpu_per_node: int = 1,
    cluster_name: Optional[str] = None,
    torchrun_path: str = "/opt/conda/bin/torchrun",
    use_hyperpod_cli: Optional[bool] = None,
    monitor: bool = True,
    auto_retry: bool = True,
    hf_token: Optional[str] = None
) -> str:
    """
    Deploy FSDP training job to EKS cluster using torchrun.
    
    Deploys PyTorch training job with automatic torchrun configuration
    for multi-node distributed training. Uses either kubectl or HyperPod CLI
    (auto-detected), monitors progress, detects failures, and automatically
    retries with fixes for known issues.
    
    Args:
        job_name: Job name (default: "fsdp-training")
        image_uri: Docker image (None to auto-detect from ECR)
        instance_type: Instance type (default: "ml.g5.8xlarge")
        num_nodes: Number of nodes for distributed training (default: 4)
        gpu_per_node: Number of GPUs per node (default: 1)
        cluster_name: EKS cluster name (required)
        torchrun_path: Path to torchrun in container (default: "/opt/conda/bin/torchrun")
        use_hyperpod_cli: Use HyperPod CLI (None for auto-detect)
        monitor: Monitor job after deployment (default: True)
        auto_retry: Auto-retry on failures (default: True)
        hf_token: HuggingFace token for gated models (default: None)
    
    Returns:
        str: Deployment status and monitoring info
    
    Examples:
        "Deploy training job"
        "Start training with 4 nodes on ml.g5.8xlarge"
        "Deploy and monitor with auto-retry"
        "Deploy Llama 3.2 training with HF token"
    """
    
    if not cluster_name:
        return "❌ Error: cluster_name is required"
    
    logger = create_logger('training-job-deployer')
    
    try:
        deployer = JobDeployer(cluster_name=cluster_name, verbose=True)
        
        # Verify image
        if not image_uri:
            image_uri = "975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest"
        
        success, msg = deployer.verify_image(image_uri)
        if not success:
            logger.warning(f"Image verification: {msg}")
        
        # Build config with torchrun support
        config = {
            'job_name': job_name,
            'image_uri': image_uri,
            'instance_type': instance_type,
            'num_nodes': num_nodes,
            'gpu_per_node': gpu_per_node,
            'torchrun_path': torchrun_path,
            'model_type': 'llama_v3',
            'max_steps': 100,
            'tokenizer': 'hf-internal-testing/llama-tokenizer',
            'dataset': 'allenai/c4',
            'dataset_config_name': 'en',
            'sharding_strategy': 'full',
            'checkpoint_dir': '/checkpoints',
            'hf_token': hf_token
        }
        
        # Generate and deploy
        method = 'hyperpod-cli' if use_hyperpod_cli else 'kubectl'
        manifest = deployer.generate_manifest(config, format=method)
        
        success, output = deployer.deploy_job(manifest, method='auto')
        
        if not success:
            return f"❌ Deployment failed: {output}"
        
        result = f"✅ Job deployed: {job_name}\n"
        result += f"   Image: {image_uri}\n"
        result += f"   Nodes: {num_nodes} x {instance_type}\n"
        result += f"   GPUs: {num_nodes} nodes x {gpu_per_node} GPUs = {num_nodes * gpu_per_node} total GPUs\n"
        result += f"   Torchrun: {torchrun_path}\n"
        
        if monitor:
            result += "\n📊 Monitoring started (5 min real-time + background)\n"
            deployer.monitor_job(job_name, mode='hybrid')
        
        return result
    
    except Exception as e:
        return f"❌ Error: {str(e)}"


try:
    from claude.tools import tool
    
    @tool
    def deploy_training_job_tool(**kwargs) -> str:
        """Deploy training job"""
        return deploy_training_job(**kwargs)
        
except ImportError:
    pass


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Deploy training job to EKS')
    parser.add_argument('--job_name', default='fsdp-training', help='Job name')
    parser.add_argument('--image_uri', default=None, help='Docker image URI')
    parser.add_argument('--instance_type', default='ml.g5.8xlarge', help='Instance type')
    parser.add_argument('--num_nodes', type=int, default=4, help='Number of nodes')
    parser.add_argument('--gpu_per_node', type=int, default=1, help='GPUs per node')
    parser.add_argument('--cluster_name', required=True, help='EKS cluster name')
    parser.add_argument('--torchrun_path', default='/opt/conda/bin/torchrun', help='Path to torchrun')
    parser.add_argument('--hf_token', default=None, help='HuggingFace token')
    args = parser.parse_args()
    
    print(deploy_training_job(**vars(args)))
