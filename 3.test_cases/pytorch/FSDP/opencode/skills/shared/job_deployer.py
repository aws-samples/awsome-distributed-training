"""
Training Job Deployer - Deploy and manage training jobs on EKS.
"""

import os
import json
import yaml
import time
import tempfile
from typing import Optional, Dict, List, Tuple
from pathlib import Path
from .k8s_utils import K8sClient, ConfigMapManager
from .logger import create_logger


class JobDeployer:
    """Deploy and manage training jobs on EKS."""
    
    def __init__(self, cluster_name: str, region: str = "us-west-2", verbose: bool = True):
        self.cluster_name = cluster_name
        self.region = region
        self.logger = create_logger('job-deployer', verbose=verbose)
        self.k8s = K8sClient(cluster_name=cluster_name, region=region)
        self.config_manager = ConfigMapManager(self.k8s)
    
    def verify_image(self, image_uri: str) -> Tuple[bool, str]:
        """Verify Docker image exists and is accessible."""
        self.logger.info(f"🔍 Verifying image: {image_uri}")
        
        # Try to pull image info
        try:
            import subprocess
            result = subprocess.run(
                ['docker', 'manifest', 'inspect', image_uri],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                return True, "Image verified"
            else:
                return False, f"Image not accessible: {result.stderr}"
        except Exception as e:
            # If docker command fails, assume it might work on cluster
            self.logger.warning(f"Could not verify image locally: {e}")
            return True, "Image verification skipped (will check on cluster)"
    
    def generate_manifest(self, config: Dict, format: str = 'kubectl') -> str:
        """Generate Kubernetes manifest."""
        job_name = config.get('job_name', 'fsdp-training')
        
        if format == 'hyperpod-cli':
            return self._generate_hyperpod_manifest(config)
        else:
            return self._generate_kubectl_manifest(config)
    
    def _generate_kubectl_manifest(self, config: Dict) -> str:
        """Generate kubectl apply compatible manifest."""
        job_name = config.get('job_name', 'fsdp-training')
        namespace = config.get('namespace', 'kubeflow')
        
        manifest = {
            'apiVersion': 'kubeflow.org/v1',
            'kind': 'PyTorchJob',
            'metadata': {
                'name': job_name,
                'namespace': namespace
            },
            'spec': {
                'pytorchReplicaSpecs': {
                    'Worker': {
                        'replicas': config.get('num_nodes', 8),
                        'template': {
                            'spec': {
                                'containers': [{
                                    'name': 'pytorch',
                                    'image': config.get('image_uri'),
                                    'command': ['/fsdp/train.py'],
                                    'args': self._build_training_args(config),
                                    'resources': {
                                        'limits': {
                                            'nvidia.com/gpu': config.get('gpu_per_node', 1),
                                            'vpc.amazonaws.com/efa': config.get('efa_per_node', 1)
                                        },
                                        'requests': {
                                            'nvidia.com/gpu': config.get('gpu_per_node', 1),
                                            'vpc.amazonaws.com/efa': config.get('efa_per_node', 1)
                                        }
                                    },
                                    'env': self._build_env_vars(config),
                                    'volumeMounts': [
                                        {'name': 'local', 'mountPath': '/local'},
                                        {'name': 'shm', 'mountPath': '/dev/shm'}
                                    ]
                                }],
                                'volumes': [
                                    {
                                        'name': 'local',
                                        'hostPath': {'path': '/mnt/k8s-disks/0'}
                                    },
                                    {
                                        'name': 'shm',
                                        'hostPath': {'path': '/dev/shm', 'type': 'Directory'}
                                    }
                                ],
                                'restartPolicy': 'OnFailure'
                            }
                        }
                    }
                }
            }
        }
        
        return yaml.dump(manifest, default_flow_style=False)
    
    def _generate_hyperpod_manifest(self, config: Dict) -> str:
        """Generate HyperPod CLI compatible manifest."""
        # HyperPod uses a different YAML structure
        manifest = {
            'defaults': ['- override hydra/job_logging: stdout'],
            'hydra': {'run': {'dir': '.', 'output_subdir': None}},
            'training_cfg': {
                'entry_script': '/fsdp/train.py',
                'script_args': self._build_training_args_dict(config)
            },
            'run': {
                'name': config.get('job_name', 'fsdp-training'),
                'nodes': config.get('num_nodes', 8),
                'ntasks_per_node': config.get('gpu_per_node', 1)
            },
            'cluster': {
                'cluster_type': 'k8s',
                'instance_type': config.get('instance_type', 'ml.g5.8xlarge'),
                'cluster_config': {
                    'namespace': config.get('namespace', 'kubeflow'),
                    'pullPolicy': 'Always',
                    'restartPolicy': 'OnFailure',
                    'volumes': [
                        {
                            'volumeName': 'local',
                            'hostPath': '/mnt/k8s-disks/0',
                            'mountPath': '/local'
                        }
                    ]
                }
            },
            'base_results_dir': './results',
            'container': config.get('image_uri'),
            'env_vars': self._build_env_vars_dict(config)
        }
        
        return yaml.dump(manifest, default_flow_style=False)
    
    def _build_training_args(self, config: Dict) -> List[str]:
        """Build training script arguments."""
        args = []
        
        # Model configuration
        model_params = {
            'max_context_width': config.get('max_context_width', 4096),
            'num_key_value_heads': config.get('num_key_value_heads', 32),
            'intermediate_size': config.get('intermediate_size', 11008),
            'hidden_width': config.get('hidden_width', 4096),
            'num_layers': config.get('num_layers', 32),
            'num_heads': config.get('num_heads', 32),
            'model_type': config.get('model_type', 'llama_v2'),
            'tokenizer': config.get('tokenizer', 'hf-internal-testing/llama-tokenizer'),
            'checkpoint_freq': config.get('checkpoint_freq', 5000),
            'validation_freq': config.get('validation_freq', 500),
            'max_steps': config.get('max_steps', 5000),
            'checkpoint_dir': config.get('checkpoint_dir', '/checkpoints'),
            'dataset': config.get('dataset', 'allenai/c4'),
            'dataset_config_name': config.get('dataset_config_name', 'en'),
            'train_batch_size': config.get('train_batch_size', 1),
            'val_batch_size': config.get('val_batch_size', 1),
            'sharding_strategy': config.get('sharding_strategy', 'full'),
            'offload_activations': config.get('offload_activations', 1)
        }
        
        for key, value in model_params.items():
            args.append(f'--{key}={value}')
        
        return args
    
    def _build_training_args_dict(self, config: Dict) -> Dict:
        """Build training args as dictionary for HyperPod CLI."""
        return {
            f'--{key}': value
            for key, value in {
                'max_context_width': config.get('max_context_width', 4096),
                'num_key_value_heads': config.get('num_key_value_heads', 32),
                'intermediate_size': config.get('intermediate_size', 11008),
                'hidden_width': config.get('hidden_width', 4096),
                'num_layers': config.get('num_layers', 32),
                'num_heads': config.get('num_heads', 32),
                'model_type': config.get('model_type', 'llama_v2'),
                'tokenizer': config.get('tokenizer', 'hf-internal-testing/llama-tokenizer'),
                'checkpoint_freq': config.get('checkpoint_freq', 5000),
                'validation_freq': config.get('validation_freq', 500),
                'max_steps': config.get('max_steps', 5000),
                'checkpoint_dir': config.get('checkpoint_dir', '/checkpoints'),
                'dataset': config.get('dataset', 'allenai/c4'),
                'dataset_config_name': config.get('dataset_config_name', 'en'),
                'train_batch_size': config.get('train_batch_size', 1),
                'val_batch_size': config.get('val_batch_size', 1),
                'sharding_strategy': config.get('sharding_strategy', 'full'),
                'offload_activations': config.get('offload_activations', 1)
            }.items()
        }
    
    def _build_env_vars(self, config: Dict) -> List[Dict]:
        """Build environment variables for containers."""
        env_vars = [
            {'name': 'NCCL_DEBUG', 'value': 'INFO'},
            {'name': 'NCCL_SOCKET_IFNAME', 'value': '^lo'},
            {'name': 'FI_PROVIDER', 'value': config.get('fi_provider', 'efa')},
            {'name': 'FI_EFA_FORK_SAFE', 'value': '1'},
            {'name': 'PYTHONUNBUFFERED', 'value': '1'}
        ]
        
        # Add HuggingFace token if provided
        if config.get('hf_token'):
            env_vars.append({'name': 'HF_TOKEN', 'value': config.get('hf_token')})
        
        return env_vars
    
    def _build_env_vars_dict(self, config: Dict) -> Dict:
        """Build environment variables as dictionary."""
        env_vars = {
            'NCCL_DEBUG': 'INFO',
            'NCCL_SOCKET_IFNAME': '^lo',
            'FI_PROVIDER': config.get('fi_provider', 'efa'),
            'FI_EFA_FORK_SAFE': '1',
            'PYTHONUNBUFFERED': '1'
        }
        
        if config.get('hf_token'):
            env_vars['HF_TOKEN'] = config.get('hf_token')
        
        return env_vars
    
    def deploy_job(self, manifest: str, method: str = 'auto') -> Tuple[bool, str]:
        """Deploy job to cluster."""
        # Auto-detect deployment method
        if method == 'auto':
            method = self._detect_deployment_method()
        
        # Write manifest to temp file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(manifest)
            manifest_path = f.name
        
        try:
            if method == 'hyperpod-cli':
                return self._deploy_with_hyperpod_cli(manifest_path)
            else:
                return self._deploy_with_kubectl(manifest_path)
        finally:
            os.unlink(manifest_path)
    
    def _detect_deployment_method(self) -> str:
        """Auto-detect best deployment method."""
        try:
            import subprocess
            result = subprocess.run(
                ['which', 'hyperpod'],
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                self.logger.info("🔧 Detected HyperPod CLI - will use for deployment")
                return 'hyperpod-cli'
        except Exception:
            pass
        
        self.logger.info("🔧 Using kubectl for deployment")
        return 'kubectl'
    
    def _deploy_with_kubectl(self, manifest_path: str) -> Tuple[bool, str]:
        """Deploy using kubectl."""
        self.logger.info("🚀 Deploying job with kubectl...")
        return self.k8s.apply_manifest(manifest_path)
    
    def _deploy_with_hyperpod_cli(self, manifest_path: str) -> Tuple[bool, str]:
        """Deploy using HyperPod CLI."""
        self.logger.info("🚀 Deploying job with HyperPod CLI...")
        
        try:
            import subprocess
            result = subprocess.run(
                ['hyperpod', 'start-job', '--config-file', manifest_path],
                capture_output=True,
                text=True,
                timeout=60
            )
            
            if result.returncode == 0:
                return True, result.stdout
            else:
                return False, result.stderr
        except Exception as e:
            return False, str(e)
    
    def monitor_job(self, job_name: str, mode: str = 'hybrid', timeout: int = 300):
        """Monitor job with hybrid approach."""
        namespace = 'kubeflow'
        
        if mode == 'hybrid':
            # Phase 1: Real-time streaming
            self.logger.info(f"📊 Monitoring job {job_name} (streaming for {timeout}s)...")
            self._stream_logs_for_duration(job_name, namespace, timeout)
            
            # Phase 2: Background monitoring
            self.logger.info("⏱️  Switching to background monitoring...")
            self._start_background_monitor(job_name, namespace)
            
        elif mode == 'stream':
            self._stream_logs_forever(job_name, namespace)
        else:  # background
            self._start_background_monitor(job_name, namespace)
    
    def _stream_logs_for_duration(self, job_name: str, namespace: str, duration: int):
        """Stream logs for specified duration."""
        start_time = time.time()
        
        # Find master pod
        master_pod = self._find_master_pod(job_name, namespace)
        if not master_pod:
            self.logger.warning("Could not find master pod")
            return
        
        self.logger.info(f"📜 Streaming logs from master pod: {master_pod}")
        
        try:
            for line in self.k8s.stream_pod_logs(master_pod, namespace):
                print(line)
                if time.time() - start_time > duration:
                    break
        except KeyboardInterrupt:
            pass
    
    def _stream_logs_forever(self, job_name: str, namespace: str):
        """Stream logs until interrupted."""
        master_pod = self._find_master_pod(job_name, namespace)
        if not master_pod:
            return
        
        try:
            for line in self.k8s.stream_pod_logs(master_pod, namespace):
                print(line)
        except KeyboardInterrupt:
            pass
    
    def _start_background_monitor(self, job_name: str, namespace: str):
        """Start background monitoring."""
        self.logger.info("✅ Job is running in background")
        self.logger.info(f"   Check status: kubectl get pytorchjob {job_name} -n {namespace}")
        self.logger.info(f"   View logs: kubectl logs -f {job_name}-worker-0 -n {namespace}")
    
    def _find_master_pod(self, job_name: str, namespace: str) -> Optional[str]:
        """Find the master pod for a job."""
        pods = self.k8s.get_pods(namespace, label_selector=f'training.kubeflow.org/job-name={job_name}')
        
        if not pods:
            return None
        
        # Usually worker-0 is the master, or we can check logs
        for pod in pods:
            if 'worker-0' in pod['name']:
                return pod['name']
        
        return pods[0]['name'] if pods else None
    
    def get_job_status(self, job_name: str) -> Dict:
        """Get current job status."""
        jobs = self.k8s.get_pytorchjobs()
        
        for job in jobs:
            if job['name'] == job_name:
                return job
        
        return {'state': 'NotFound'}
    
    def stop_job(self, job_name: str) -> Tuple[bool, str]:
        """Stop/delete a job."""
        self.logger.info(f"🛑 Stopping job: {job_name}")
        return self.k8s.delete_pytorchjob(job_name)
