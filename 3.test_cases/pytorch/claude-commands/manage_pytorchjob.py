#!/usr/bin/env python3
"""
Claude Code Command: Manage PyTorchJob
Create, monitor, and manage PyTorchJob resources on Amazon EKS for distributed training.

Examples:
    "create a pytorchjob named training-job with 4 workers and 8 gpus each"
    "list all pytorchjobs in the default namespace"
    "get status of pytorchjob training-job"
    "delete pytorchjob training-job"
    "check if pytorchjob crd is installed"
"""

import json
import subprocess
import sys
import os
from typing import Optional, Dict, Any
from pathlib import Path

# Add skill src path for direct imports
SKILL_PATH = Path(__file__).parent.parent / "opencode" / "skills" / "pytorchjob-manager" / "src"
sys.path.insert(0, str(SKILL_PATH))


def _run_skill_function(func_name: str, *args, **kwargs) -> Any:
    """Run a skill function via direct import."""
    try:
        from pytorchjob_manager import (
            check_pytorchjob_crd, generate_pytorchjob_yaml, deploy_pytorchjob,
            get_pytorchjob_status, delete_pytorchjob, list_pytorchjobs,
            get_pytorchjob_logs
        )
        
        functions = {
            'check_pytorchjob_crd': check_pytorchjob_crd,
            'generate_pytorchjob_yaml': generate_pytorchjob_yaml,
            'deploy_pytorchjob': deploy_pytorchjob,
            'get_pytorchjob_status': get_pytorchjob_status,
            'delete_pytorchjob': delete_pytorchjob,
            'list_pytorchjobs': list_pytorchjobs,
            'get_pytorchjob_logs': get_pytorchjob_logs,
        }
        
        if func_name not in functions:
            return {"error": f"Unknown function: {func_name}"}
        
        return functions[func_name](*args, **kwargs)
    except ImportError as e:
        return {"error": f"Failed to import pytorchjob_manager: {e}"}
    except Exception as e:
        return {"error": str(e)}


def check_crd() -> str:
    """Check if PyTorchJob CRD is installed on the cluster."""
    result = subprocess.run(
        ["kubectl", "get", "crd", "pytorchjobs.kubeflow.org"],
        capture_output=True,
        text=True
    )
    if result.returncode == 0:
        return "✅ PyTorchJob CRD is installed"
    return "❌ PyTorchJob CRD not found. Install Kubeflow Training Operator first."


def list_jobs(namespace: str = "default") -> str:
    """List all PyTorchJobs in a namespace."""
    try:
        result = subprocess.run(
            ["kubectl", "get", "pytorchjobs", "-n", namespace, "-o", "json"],
            capture_output=True,
            text=True,
            check=True
        )
        data = json.loads(result.stdout)
        jobs = data.get("items", [])
        
        if not jobs:
            return f"No PyTorchJobs found in namespace '{namespace}'"
        
        lines = [f"PyTorchJobs in namespace '{namespace}':\n"]
        lines.append(f"{'NAME':<30} {'PHASE':<15} {'AGE':<20}")
        lines.append("-" * 65)
        
        for job in jobs:
            metadata = job.get("metadata", {})
            status = job.get("status", {})
            name = metadata.get("name", "unknown")
            age = metadata.get("creationTimestamp", "unknown")
            
            # Get phase from conditions
            phase = "Unknown"
            conditions = status.get("conditions", [])
            for condition in reversed(conditions):
                if condition.get("status") == "True":
                    phase = condition.get("type", "Unknown")
                    break
            
            lines.append(f"{name:<30} {phase:<15} {age:<20}")
        
        return "\n".join(lines)
    
    except subprocess.CalledProcessError as e:
        return f"❌ Failed to list jobs: {e.stderr}"


def get_status(name: str, namespace: str = "default") -> str:
    """Get detailed status of a PyTorchJob."""
    try:
        result = subprocess.run(
            ["kubectl", "get", "pytorchjob", name, "-n", namespace, "-o", "json"],
            capture_output=True,
            text=True,
            check=True
        )
        data = json.loads(result.stdout)
        status = data.get("status", {})
        
        lines = [f"PyTorchJob: {name}", f"Namespace: {namespace}\n"]
        
        # Phase
        phase = "Unknown"
        conditions = status.get("conditions", [])
        for condition in reversed(conditions):
            if condition.get("status") == "True":
                phase = condition.get("type", "Unknown")
                break
        lines.append(f"Phase: {phase}")
        
        if status.get("startTime"):
            lines.append(f"Start Time: {status['startTime']}")
        if status.get("completionTime"):
            lines.append(f"Completion Time: {status['completionTime']}")
        
        # Replica statuses
        replica_statuses = status.get("replicaStatuses", {})
        if replica_statuses:
            lines.append("\nReplica Statuses:")
            for replica_type, replica_status in replica_statuses.items():
                active = replica_status.get("active", 0)
                succeeded = replica_status.get("succeeded", 0)
                failed = replica_status.get("failed", 0)
                lines.append(f"  {replica_type}: active={active}, succeeded={succeeded}, failed={failed}")
        
        return "\n".join(lines)
    
    except subprocess.CalledProcessError as e:
        return f"❌ Failed to get status: {e.stderr}"


def delete_job(name: str, namespace: str = "default") -> str:
    """Delete a PyTorchJob."""
    try:
        result = subprocess.run(
            ["kubectl", "delete", "pytorchjob", name, "-n", namespace],
            capture_output=True,
            text=True,
            check=True
        )
        return f"✅ Deleted PyTorchJob '{name}' in namespace '{namespace}'\n{result.stdout.strip()}"
    except subprocess.CalledProcessError as e:
        return f"❌ Failed to delete job: {e.stderr}"


def create_job(
    name: str,
    image: str,
    num_workers: int = 2,
    num_gpus_per_worker: int = 1,
    namespace: str = "default",
    command: Optional[list] = None,
    env: Optional[Dict[str, str]] = None
) -> str:
    """
    Create a new PyTorchJob.
    
    Args:
        name: Job name
        image: Container image
        num_workers: Number of worker nodes
        num_gpus_per_worker: GPUs per worker
        namespace: Kubernetes namespace
        command: Training command as list
        env: Environment variables dict
    
    Returns:
        Status message
    """
    if command is None:
        command = ["python", "train.py"]
    if env is None:
        env = {}
    
    # Build config
    config = {
        "name": name,
        "namespace": namespace,
        "image": image,
        "num_workers": num_workers,
        "num_gpus_per_worker": num_gpus_per_worker,
        "command": command,
        "env": env
    }
    
    # Generate YAML using skill
    skill_script = SKILL_PATH / "pytorchjob_manager.py"
    
    yaml_cmd = [
        sys.executable, "-c",
        f"""
import sys
sys.path.insert(0, '{SKILL_PATH}')
from pytorchjob_manager import generate_pytorchjob_yaml
config = {config}
yaml_content = generate_pytorchjob_yaml(config)
print(yaml_content)
"""
    ]
    
    try:
        result = subprocess.run(yaml_cmd, capture_output=True, text=True, check=True)
        yaml_content = result.stdout
        
        # Write to temp file and apply
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(yaml_content)
            temp_path = f.name
        
        apply_result = subprocess.run(
            ["kubectl", "apply", "-f", temp_path],
            capture_output=True,
            text=True,
            check=True
        )
        
        Path(temp_path).unlink()
        
        return f"✅ Created PyTorchJob '{name}'\n{apply_result.stdout.strip()}"
    
    except subprocess.CalledProcessError as e:
        return f"❌ Failed to create job: {e.stderr}"


def manage_pytorchjob(
    action: str,
    name: Optional[str] = None,
    namespace: str = "default",
    image: Optional[str] = None,
    num_workers: int = 2,
    num_gpus_per_worker: int = 1,
    command: Optional[str] = None
) -> str:
    """
    Manage PyTorchJob resources on EKS.
    
    Create, delete, list, or get status of PyTorchJobs for distributed training.
    
    Args:
        action: One of "create", "delete", "list", "status", "logs", "check_crd"
        name: Job name (required for create, delete, status, logs)
        namespace: Kubernetes namespace (default: "default")
        image: Container image (required for create)
        num_workers: Number of workers (default: 2)
        num_gpus_per_worker: GPUs per worker (default: 1)
        command: Training command as string (default: "python train.py")
    
    Returns:
        Status message or job information
    
    Examples:
        "manage_pytorchjob('check_crd')"
        "manage_pytorchjob('list')"
        "manage_pytorchjob('status', name='my-job')"
        "manage_pytorchjob('logs', name='my-job')"
        "manage_pytorchjob('delete', name='my-job')"
        "manage_pytorchjob('create', name='training', image='pytorch/pytorch:latest', num_workers=4)"
    """
    
    action = action.lower()
    
    if action == "check_crd":
        return check_crd()
    
    elif action == "list":
        return list_jobs(namespace)
    
    elif action == "status":
        if not name:
            return "❌ Job name required for status action"
        return get_status(name, namespace)
    
    elif action == "logs":
        if not name:
            return "❌ Job name required for logs action"
        result = _run_skill_function('get_pytorchjob_logs', name=name, namespace=namespace)
        if isinstance(result, dict) and 'error' in result:
            return f"❌ Failed to get logs: {result['error']}"
        return str(result) if result else "No logs found"
    
    elif action == "delete":
        if not name:
            return "❌ Job name required for delete action"
        return delete_job(name, namespace)
    
    elif action == "create":
        if not name:
            return "❌ Job name required for create action"
        if not image:
            return "❌ Container image required for create action"
        
        cmd_list = None
        if command:
            cmd_list = command.split()
        
        return create_job(
            name=name,
            image=image,
            num_workers=num_workers,
            num_gpus_per_worker=num_gpus_per_worker,
            namespace=namespace,
            command=cmd_list
        )
    
    else:
        return f"❌ Unknown action: {action}. Use: create, delete, list, status, logs, check_crd"


# Claude Code tool registration
try:
    from claude.tools import tool
    
    @tool
    def manage_pytorchjob_tool(
        action: str,
        name: Optional[str] = None,
        namespace: str = "default",
        image: Optional[str] = None,
        num_workers: int = 2,
        num_gpus_per_worker: int = 1,
        command: Optional[str] = None
    ) -> str:
        """Manage PyTorchJob resources on EKS"""
        return manage_pytorchjob(action, name, namespace, image, num_workers, num_gpus_per_worker, command)
        
except ImportError:
    pass


if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Manage PyTorchJobs on EKS')
    parser.add_argument('action', choices=['create', 'delete', 'list', 'status', 'logs', 'check_crd'])
    parser.add_argument('--name', default=None, help='Job name')
    parser.add_argument('--namespace', default='default', help='Kubernetes namespace')
    parser.add_argument('--image', default=None, help='Container image (for create)')
    parser.add_argument('--num_workers', type=int, default=2, help='Number of workers')
    parser.add_argument('--num_gpus_per_worker', type=int, default=1, help='GPUs per worker')
    parser.add_argument('--command', default=None, help='Training command')
    
    args = parser.parse_args()
    
    print(manage_pytorchjob(**vars(args)))
