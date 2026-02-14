#!/usr/bin/env python3
"""
Claude Code Command: Deploy Training Job
Deploy training jobs to EKS using PyTorchJob (torchrun) or Ray (KubeRay).
"""

from typing import Optional
import sys
import os
import subprocess

def deploy_training_job(
    job_name: str = "fsdp-training",
    image_uri: Optional[str] = None,
    instance_type: str = "ml.g5.8xlarge",
    num_nodes: int = 4,
    gpu_per_node: int = 1,
    cluster_name: Optional[str] = None,
    torchrun_path: str = "/opt/conda/bin/torchrun",
    use_ray: bool = False,
    install_ray: bool = False,
    use_hyperpod_cli: Optional[bool] = None,
    monitor: bool = True,
    auto_retry: bool = True,
    hf_token: Optional[str] = None
) -> str:
    """
    Deploy distributed training job to EKS using PyTorchJob (torchrun) or Ray (KubeRay).
    
    **PyTorchJob Mode (Default):**
    - Uses torchrun for distributed training
    - Kubeflow PyTorchJob for orchestration
    - Automatic torchrun configuration
    
    **Ray Mode (Optional):**
    - Uses Ray (KubeRay) for distributed training
    - Alternative to PyTorchJob
    - Good for Ray-based workloads
    
    Args:
        job_name: Job name (default: "fsdp-training")
        image_uri: Docker image (None to auto-detect from ECR)
        instance_type: Instance type (default: "ml.g5.8xlarge")
        num_nodes: Number of nodes for distributed training (default: 4)
        gpu_per_node: Number of GPUs per node (default: 1)
        cluster_name: EKS cluster name (required)
        torchrun_path: Path to torchrun in container (default: "/opt/conda/bin/torchrun")
        use_ray: Use Ray (KubeRay) instead of PyTorchJob (default: False)
        install_ray: Install KubeRay operator if not present (default: False)
        use_hyperpod_cli: Use HyperPod CLI (None for auto-detect)
        monitor: Monitor job after deployment (default: True)
        auto_retry: Auto-retry on failures (default: True)
        hf_token: HuggingFace token for gated models (default: None)
    
    Returns:
        str: Deployment status and monitoring info
    
    Examples:
        "Deploy training job"
        "Deploy with 4 nodes on ml.g5.8xlarge"
        "Deploy using Ray"
        "Deploy and monitor with auto-retry"
    """
    
    if not cluster_name:
        return "❌ Error: cluster_name is required"
    
    # Build command
    cmd = [
        'python3',
        os.path.join(os.path.dirname(__file__), '..', 'opencode', 'skills',
                    'training-job-deployer', 'src', 'deploy_job.py'),
        '--job_name', job_name,
        '--cluster_name', cluster_name,
        '--instance_type', instance_type,
        '--num_nodes', str(num_nodes),
        '--gpu_per_node', str(gpu_per_node),
        '--torchrun_path', torchrun_path
    ]
    
    if image_uri:
        cmd.extend(['--image_uri', image_uri])
    
    if use_ray:
        cmd.append('--use_ray')
    
    if install_ray:
        cmd.append('--install_ray')
    
    if use_hyperpod_cli is not None:
        cmd.extend(['--use_hyperpod_cli', 'true' if use_hyperpod_cli else 'false'])
    
    if hf_token:
        cmd.extend(['--hf_token', hf_token])
    
    if monitor:
        cmd.append('--monitor')
    
    if auto_retry:
        cmd.append('--auto_retry')
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        
        if result.returncode == 0:
            return f"✅ Deployment successful\n\n{result.stdout}"
        else:
            return f"❌ Deployment failed\n\n{result.stderr}\n\n{result.stdout}"
    
    except subprocess.TimeoutExpired:
        return "❌ Deployment timeout after 300 seconds"
    except Exception as e:
        return f"❌ Error: {str(e)}"


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
    parser.add_argument('--use_ray', action='store_true', help='Use Ray (KubeRay)')
    parser.add_argument('--install_ray', action='store_true', help='Install KubeRay operator')
    parser.add_argument('--hf_token', default=None, help='HuggingFace token')
    args = parser.parse_args()
    
    print(deploy_training_job(**vars(args)))
