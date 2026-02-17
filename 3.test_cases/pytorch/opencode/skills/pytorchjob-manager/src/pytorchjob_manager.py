"""PyTorchJob Manager - Deploy and manage distributed training jobs on EKS."""

import json
import subprocess
import tempfile
from pathlib import Path
from typing import Any

import yaml

try:
    from .logger import get_logger
except ImportError:
    from logger import get_logger

logger = get_logger()


def check_pytorchjob_crd() -> bool:
    """Check if PyTorchJob CRD is installed on the cluster."""
    try:
        result = subprocess.run(
            ["kubectl", "get", "crd", "pytorchjobs.kubeflow.org"],
            capture_output=True,
            text=True,
            check=True
        )
        logger.info("PyTorchJob CRD is installed")
        return True
    except subprocess.CalledProcessError:
        logger.error("PyTorchJob CRD not found. Install Kubeflow Training Operator.")
        return False


def generate_pytorchjob_yaml(config: dict[str, Any]) -> str:
    """Generate PyTorchJob YAML with FSDP support.
    
    Args:
        config: Dictionary containing job configuration
        
    Returns:
        YAML string for the PyTorchJob
    """
    name = config.get("name", "pytorch-job")
    namespace = config.get("namespace", "default")
    image = config.get("image", "pytorch/pytorch:latest")
    num_workers = config.get("num_workers", 2)
    num_gpus_per_worker = config.get("num_gpus_per_worker", 1)
    command = config.get("command", ["python", "train.py"])
    env = config.get("env", {})
    fsdp_config = config.get("fsdp_config", {})
    resources = config.get("resources", {})
    volumes = config.get("volumes", [])
    
    # Build environment variables
    env_list = [{"name": k, "value": str(v)} for k, v in env.items()]
    
    # Add FSDP-specific environment variables
    if fsdp_config:
        if "FSDP_STATE_DICT_TYPE" not in env:
            env_list.append({"name": "FSDP_STATE_DICT_TYPE", "value": "SHARDED_STATE_DICT"})
        if "NCCL_DEBUG" not in env:
            env_list.append({"name": "NCCL_DEBUG", "value": "INFO"})
    
    # Build resource requirements
    resource_reqs = {
        "limits": {
            "nvidia.com/gpu": str(num_gpus_per_worker)
        },
        "requests": {
            "nvidia.com/gpu": str(num_gpus_per_worker)
        }
    }
    
    if "memory" in resources:
        resource_reqs["limits"]["memory"] = resources["memory"]
        resource_reqs["requests"]["memory"] = resources["memory"]
    
    if "cpu" in resources:
        resource_reqs["limits"]["cpu"] = resources["cpu"]
        resource_reqs["requests"]["cpu"] = resources["cpu"]
    
    # Build volume mounts
    volume_mounts = []
    volumes_spec = []
    
    for vol in volumes:
        vol_name = vol.get("name", "volume")
        volume_mounts.append({
            "name": vol_name,
            "mountPath": vol.get("mountPath", "/data")
        })
        volumes_spec.append({
            "name": vol_name,
            **vol.get("spec", {})
        })
    
    # Build the PyTorchJob spec
    pytorchjob = {
        "apiVersion": "kubeflow.org/v1",
        "kind": "PyTorchJob",
        "metadata": {
            "name": name,
            "namespace": namespace
        },
        "spec": {
            "pytorchReplicaSpecs": {
                "Master": {
                    "replicas": 1,
                    "restartPolicy": "OnFailure",
                    "template": {
                        "spec": {
                            "containers": [
                                {
                                    "name": "pytorch",
                                    "image": image,
                                    "command": command,
                                    "env": env_list,
                                    "resources": resource_reqs,
                                    "volumeMounts": volume_mounts if volume_mounts else None
                                }
                            ],
                            "volumes": volumes_spec if volumes_spec else None
                        }
                    }
                },
                "Worker": {
                    "replicas": num_workers - 1 if num_workers > 1 else 1,
                    "restartPolicy": "OnFailure",
                    "template": {
                        "spec": {
                            "containers": [
                                {
                                    "name": "pytorch",
                                    "image": image,
                                    "command": command,
                                    "env": env_list,
                                    "resources": resource_reqs,
                                    "volumeMounts": volume_mounts if volume_mounts else None
                                }
                            ],
                            "volumes": volumes_spec if volumes_spec else None
                        }
                    }
                }
            }
        }
    }
    
    # Clean up None values
    def clean_none(d):
        if isinstance(d, dict):
            return {k: clean_none(v) for k, v in d.items() if v is not None}
        elif isinstance(d, list):
            return [clean_none(v) for v in d if v is not None]
        return d
    
    pytorchjob = clean_none(pytorchjob)
    
    return yaml.dump(pytorchjob, default_flow_style=False, sort_keys=False)


def deploy_pytorchjob(yaml_content: str) -> bool:
    """Deploy PyTorchJob to the cluster.
    
    Args:
        yaml_content: YAML content for the PyTorchJob
        
    Returns:
        True if deployment successful, False otherwise
    """
    try:
        # Write YAML to temporary file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(yaml_content)
            temp_path = f.name
        
        # Apply with kubectl
        result = subprocess.run(
            ["kubectl", "apply", "-f", temp_path],
            capture_output=True,
            text=True,
            check=True
        )
        
        # Clean up temp file
        Path(temp_path).unlink()
        
        logger.info(f"PyTorchJob deployed: {result.stdout.strip()}")
        return True
        
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to deploy PyTorchJob: {e.stderr}")
        return False


def get_pytorchjob_status(name: str, namespace: str = "default") -> dict[str, Any]:
    """Get status of a PyTorchJob.
    
    Args:
        name: Name of the PyTorchJob
        namespace: Kubernetes namespace
        
    Returns:
        Dictionary with status information
    """
    try:
        result = subprocess.run(
            ["kubectl", "get", "pytorchjob", name, "-n", namespace, "-o", "json"],
            capture_output=True,
            text=True,
            check=True
        )
        
        job_data = json.loads(result.stdout)
        status = job_data.get("status", {})
        
        return {
            "name": name,
            "namespace": namespace,
            "conditions": status.get("conditions", []),
            "replicaStatuses": status.get("replicaStatuses", {}),
            "startTime": status.get("startTime"),
            "completionTime": status.get("completionTime"),
            "phase": _get_phase(status)
        }
        
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to get PyTorchJob status: {e.stderr}")
        return {"error": e.stderr}
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse PyTorchJob status: {e}")
        return {"error": str(e)}


def _get_phase(status: dict) -> str:
    """Extract phase from status conditions."""
    conditions = status.get("conditions", [])
    for condition in reversed(conditions):
        if condition.get("status") == "True":
            return condition.get("type", "Unknown")
    return "Unknown"


def delete_pytorchjob(name: str, namespace: str = "default") -> bool:
    """Delete a PyTorchJob from the cluster.
    
    Args:
        name: Name of the PyTorchJob
        namespace: Kubernetes namespace
        
    Returns:
        True if deletion successful, False otherwise
    """
    try:
        result = subprocess.run(
            ["kubectl", "delete", "pytorchjob", name, "-n", namespace],
            capture_output=True,
            text=True,
            check=True
        )
        
        logger.info(f"PyTorchJob deleted: {result.stdout.strip()}")
        return True
        
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to delete PyTorchJob: {e.stderr}")
        return False


def list_pytorchjobs(namespace: str = "default") -> list[dict[str, Any]]:
    """List all PyTorchJobs in a namespace.
    
    Args:
        namespace: Kubernetes namespace
        
    Returns:
        List of PyTorchJob summaries
    """
    try:
        result = subprocess.run(
            ["kubectl", "get", "pytorchjobs", "-n", namespace, "-o", "json"],
            capture_output=True,
            text=True,
            check=True
        )
        
        data = json.loads(result.stdout)
        jobs = data.get("items", [])
        
        return [
            {
                "name": job.get("metadata", {}).get("name"),
                "namespace": namespace,
                "phase": _get_phase(job.get("status", {})),
                "age": job.get("metadata", {}).get("creationTimestamp")
            }
            for job in jobs
        ]
        
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to list PyTorchJobs: {e.stderr}")
        return []
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse PyTorchJobs list: {e}")
        return []


def get_pytorchjob_logs(name: str, namespace: str = "default", follow: bool = False) -> str:
    """Get logs from a PyTorchJob.
    
    Args:
        name: Name of the PyTorchJob
        namespace: Kubernetes namespace
        follow: Whether to stream logs (blocks if True)
        
    Returns:
        Logs as string, or empty string if failed
    """
    try:
        cmd = ["kubectl", "logs", "-l", f"job-name={name}", "-n", namespace]
        if follow:
            cmd.append("-f")
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True
        )
        
        return result.stdout
        
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to get logs: {e.stderr}")
        return ""
