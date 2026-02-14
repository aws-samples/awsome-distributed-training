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
    num_nodes: int = 8,
    cluster_name: Optional[str] = None,
    use_hyperpod_cli: Optional[bool] = None,
    monitor: bool = True,
    auto_retry: bool = True
) -> str:
    """
    Deploy FSDP training job to EKS cluster.
    
    Deploys PyTorch training job using either kubectl or HyperPod CLI
    (auto-detected), monitors progress, detects failures, and automatically
    retries with fixes for known issues.
    
    Args:
        job_name: Job name (default: "fsdp-training")
        image_uri: Docker image (None to auto-detect from ECR)
        instance_type: Instance type (default: "ml.g5.8xlarge")
        num_nodes: Number of nodes (default: 8)
        cluster_name: EKS cluster name (required)
        use_hyperpod_cli: Use HyperPod CLI (None for auto-detect)
        monitor: Monitor job after deployment (default: True)
        auto_retry: Auto-retry on failures (default: True)
    
    Returns:
        str: Deployment status and monitoring info
    
    Examples:
        "Deploy training job"
        "Start training with 4 nodes on ml.g5.8xlarge"
        "Deploy and monitor with auto-retry"
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
        
        # Build config
        config = {
            'job_name': job_name,
            'image_uri': image_uri,
            'instance_type': instance_type,
            'num_nodes': num_nodes,
            'model_type': 'llama_v3',
            'max_steps': 100
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
    parser = argparse.ArgumentParser()
    parser.add_argument('--job_name', default='fsdp-training')
    parser.add_argument('--image_uri', default=None)
    parser.add_argument('--instance_type', default='ml.g5.8xlarge')
    parser.add_argument('--num_nodes', type=int, default=8)
    parser.add_argument('--cluster_name', required=True)
    args = parser.parse_args()
    
    print(deploy_training_job(**vars(args)))
