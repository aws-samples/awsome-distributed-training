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


def generate_production_raycluster_yaml(
    job_name: str,
    image_uri: str,
    num_nodes: int = 4,
    checkpoint_pvc: str = "fsx-claim",
    use_efia: bool = True
) -> str:
    """Generate a production-ready RayCluster YAML with EFA and persistent storage.
    
    This function creates a complete RayCluster configuration with:
    - EFA (Elastic Fabric Adapter) for high-performance networking
    - Persistent storage for checkpoints
    - NCCL safeguards for stability
    - Proper security context for EFA
    
    Args:
        job_name: Name for the RayCluster
        image_uri: Docker image URI
        num_nodes: Number of nodes (including head)
        checkpoint_pvc: Name of the PersistentVolumeClaim for checkpoints
        use_efia: Whether to enable EFA (recommended for g5/p4d/p5 instances)
    
    Returns:
        Complete RayCluster YAML as string
    """
    
    efa_resources = '''              vpc.amazonaws.com/efa: "1"
            requests:
              vpc.amazonaws.com/efa: "1"''' if use_efia else ""
    
    efa_env = '''          - name: FI_PROVIDER
            value: "efa"
          - name: FI_EFA_USE_DEVICE_RDMA
            value: "0"
          - name: FI_EFA_FORK_SAFE
            value: "1"''' if use_efia else ""
    
    security_context = '''          securityContext:
            capabilities:
              add:
              - IPC_LOCK
              - SYS_RESOURCE''' if use_efia else ""
    
    yaml_content = f'''apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: {job_name}
  namespace: default
spec:
  headGroupSpec:
    rayStartParams:
      dashboard-host: "0.0.0.0"
      num-gpus: "1"
      block: "true"
    template:
      spec:
        containers:
        - name: ray-head
          image: {image_uri}
          resources:
            limits:
              cpu: "4"
              memory: 16Gi
              nvidia.com/gpu: "1"
{efa_resources}
          env:
          - name: NCCL_DEBUG
            value: "INFO"
          - name: NCCL_TIMEOUT
            value: "1800"
          - name: TORCH_NCCL_TRACE_BUFFER_SIZE
            value: "4096"
          - name: PYTHONUNBUFFERED
            value: "1"
          - name: NCCL_PROTO
            value: "simple"
{efa_env}
{security_context}
          ports:
          - containerPort: 6379
            name: gcs-server
          - containerPort: 8265
            name: dashboard
          - containerPort: 10001
            name: client
          volumeMounts:
          - name: checkpoints
            mountPath: /checkpoints
          - name: shm
            mountPath: /dev/shm
        volumes:
        - name: checkpoints
          persistentVolumeClaim:
            claimName: {checkpoint_pvc}
        - name: shm
          emptyDir:
            medium: Memory
            sizeLimit: 16Gi
  workerGroupSpecs:
  - replicas: {num_nodes - 1}
    minReplicas: {num_nodes - 1}
    maxReplicas: {num_nodes - 1}
    groupName: worker-group
    rayStartParams:
      num-gpus: "1"
      block: "true"
    template:
      spec:
        containers:
        - name: ray-worker
          image: {image_uri}
          resources:
            limits:
              cpu: "4"
              memory: 16Gi
              nvidia.com/gpu: "1"
{efa_resources}
          env:
          - name: NCCL_DEBUG
            value: "INFO"
          - name: NCCL_TIMEOUT
            value: "1800"
          - name: TORCH_NCCL_TRACE_BUFFER_SIZE
            value: "4096"
          - name: PYTHONUNBUFFERED
            value: "1"
          - name: NCCL_PROTO
            value: "simple"
{efa_env}
{security_context}
          volumeMounts:
          - name: checkpoints
            mountPath: /checkpoints
          - name: shm
            mountPath: /dev/shm
        volumes:
        - name: checkpoints
          persistentVolumeClaim:
            claimName: {checkpoint_pvc}
        - name: shm
          emptyDir:
            medium: Memory
            sizeLimit: 16Gi
'''
    return yaml_content


def generate_auto_restart_monitor_script(
    job_name: str,
    head_pod: str,
    checkpoint_dir: str,
    max_retries: int = 10,
    retry_delay: int = 60,
    check_interval: int = 30
) -> str:
    """Generate an auto-restart monitor script for Ray training jobs.
    
    This script monitors a Ray training job and automatically restarts it
    from the last checkpoint if it fails.
    
    Args:
        job_name: Name of the RayCluster
        head_pod: Name of the Ray head pod
        checkpoint_dir: Directory where checkpoints are stored
        max_retries: Maximum number of restart attempts
        retry_delay: Seconds to wait between retries
        check_interval: Seconds between status checks
    
    Returns:
        Python script as string
    """
    
    script_content = f'''#!/usr/bin/env python3
"""
Auto-restart monitor for Ray training job: {job_name}
Generated by training-job-deployer skill
"""

import subprocess
import time
import sys
import re
from datetime import datetime

class TrainingMonitor:
    def __init__(self):
        self.head_pod = "{head_pod}"
        self.checkpoint_dir = "{checkpoint_dir}"
        self.max_retries = {max_retries}
        self.retry_delay = {retry_delay}
        self.check_interval = {check_interval}
        self.retry_count = 0
        
    def log(self, msg, level="INFO"):
        colors = {{"INFO": "\\033[92m", "WARN": "\\033[93m", "ERROR": "\\033[91m", "RESET": "\\033[0m"}}
        ts = datetime.now().strftime("%H:%M:%S")
        print(f"{{colors.get(level, colors['INFO'])}}[{{level}}]{{colors['RESET']}} {{ts}} - {{msg}}")
        
    def run_kubectl(self, cmd, timeout=30):
        try:
            result = subprocess.run(
                cmd, shell=True, capture_output=True, text=True, timeout=timeout
            )
            return result.returncode == 0, result.stdout, result.stderr
        except Exception as e:
            return False, "", str(e)
            
    def get_latest_checkpoint(self):
        success, stdout, stderr = self.run_kubectl(
            f'kubectl exec {{self.head_pod}} -- ls -1 {{self.checkpoint_dir}}'
        )
        
        if not success:
            return None, 0
            
        steps = []
        for line in stdout.strip().split('\\n'):
            if line.startswith('global_step_'):
                try:
                    step = int(line.replace('global_step_', ''))
                    steps.append(step)
                except:
                    pass
                    
        if steps:
            latest = max(steps)
            return f"{{self.checkpoint_dir}}/global_step_{{latest}}", latest
        return None, 0
        
    def submit_job(self, checkpoint=None):
        self.log("Submitting training job...")
        
        if checkpoint:
            self.log(f"Resuming from: {{checkpoint}}")
            resume_args = f'trainer.resume_mode=auto trainer.resume_from_path="{{checkpoint}}"'
        else:
            self.log("Starting from scratch")
            resume_args = ""
            
        cmd = f"""kubectl exec {{self.head_pod}} -- bash -c '
export RAY_DATA_HOME="/checkpoints"
cd /workspace/verl
ray job submit --no-wait --working-dir "/workspace/verl" -- python3 -m verl.trainer.main_ppo algorithm.adv_estimator=grpo data.train_files="/checkpoints/data/gsm8k/train.parquet" data.val_files="/checkpoints/data/gsm8k/test.parquet" data.prompt_key=question data.train_batch_size=8 data.max_prompt_length=512 data.max_response_length=1024 data.filter_overlong_prompts=True data.truncation=error actor_rollout_ref.model.path="Qwen/Qwen2.5-0.5B" actor_rollout_ref.model.use_remove_padding=True actor_rollout_ref.model.enable_gradient_checkpointing=True actor_rollout_ref.actor.optim.lr=1e-6 actor_rollout_ref.actor.ppo_mini_batch_size=8 actor_rollout_ref.actor.ppo_micro_batch_size_per_gpu=1 actor_rollout_ref.actor.use_kl_loss=True actor_rollout_ref.actor.kl_loss_coef=0.001 actor_rollout_ref.actor.kl_loss_type=low_var_kl actor_rollout_ref.actor.entropy_coeff=0 actor_rollout_ref.rollout.log_prob_micro_batch_size_per_gpu=32 actor_rollout_ref.rollout.tensor_model_parallel_size=2 actor_rollout_ref.rollout.name=vllm actor_rollout_ref.rollout.gpu_memory_utilization=0.6 actor_rollout_ref.rollout.n=2 actor_rollout_ref.ref.log_prob_micro_batch_size_per_gpu=32 actor_rollout_ref.ref.fsdp_config.param_offload=True algorithm.use_kl_in_reward=False trainer.critic_warmup=0 trainer.logger="[console]" trainer.project_name="GRPO" trainer.experiment_name="{job_name}" trainer.n_gpus_per_node=1 trainer.nnodes=4 trainer.default_local_dir="{{self.checkpoint_dir}}" trainer.save_freq=10 trainer.test_freq=2 trainer.total_epochs=2 {{resume_args}}
' 2>&1 | grep "Job '\" | head -1"""
        
        success, stdout, stderr = self.run_kubectl(cmd, timeout=60)
        
        if success and 'raysubmit_' in stdout:
            match = re.search(r"raysubmit_[a-zA-Z0-9]+", stdout)
            if match:
                return match.group(0)
                
        self.log(f"Failed to submit job: {{stdout}} {{stderr}}", "ERROR")
        return None
        
    def check_status(self, job_id):
        success, stdout, stderr = self.run_kubectl(
            f'kubectl exec {{self.head_pod}} -- ray job status {{job_id}}'
        )
        
        if success:
            for line in stdout.split('\\n'):
                if 'Status' in line:
                    return line.split(':')[1].strip()
        return "UNKNOWN"
        
    def get_current_step(self, job_id):
        success, stdout, stderr = self.run_kubectl(
            f'kubectl exec {{self.head_pod}} -- ray job logs {{job_id}} 2>&1 | grep "step:" | tail -1'
        )
        
        if success:
            match = re.search(r'step:(\\d+)', stdout)
            if match:
                return int(match.group(1))
        return 0
        
    def monitor_job(self, job_id):
        self.log(f"Monitoring job: {{job_id}}")
        last_step = 0
        stagnation = 0
        
        while True:
            time.sleep(self.check_interval)
            
            status = self.check_status(job_id)
            self.log(f"Status: {{status}}")
            
            if status == "SUCCEEDED":
                return True
                
            if status in ["FAILED", "STOPPED"]:
                return False
                
            if status == "RUNNING":
                step = self.get_current_step(job_id)
                if step > last_step:
                    self.log(f"Progress: Step {{step}}")
                    last_step = step
                    stagnation = 0
                else:
                    stagnation += 1
                    if stagnation >= 20:
                        self.log("No progress for 10 minutes!", "WARN")
                        
    def run(self):
        self.log("=" * 60)
        self.log("Auto-Restart Training Monitor")
        self.log("=" * 60)
        
        while self.retry_count < self.max_retries:
            self.retry_count += 1
            self.log(f"Attempt {{self.retry_count}}/{{self.max_retries}}")
            
            checkpoint, step = self.get_latest_checkpoint()
            if checkpoint:
                self.log(f"Found checkpoint at step {{step}}")
            
            job_id = self.submit_job(checkpoint)
            if not job_id:
                time.sleep(self.retry_delay)
                continue
                
            self.log(f"Job ID: {{job_id}}")
            
            if self.monitor_job(job_id):
                self.log("Training completed!")
                return 0
            else:
                self.log("Job failed, restarting...", "WARN")
                time.sleep(self.retry_delay)
                
        self.log("Max retries reached", "ERROR")
        return 1

if __name__ == "__main__":
    monitor = TrainingMonitor()
    try:
        sys.exit(monitor.run())
    except KeyboardInterrupt:
        monitor.log("Interrupted", "WARN")
        sys.exit(130)
'''
    return script_content


if __name__ == '__main__':
    sys.exit(main())
