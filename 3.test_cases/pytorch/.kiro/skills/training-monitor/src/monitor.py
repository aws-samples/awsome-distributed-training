#!/usr/bin/env python3
"""
Training Monitor - Automatically monitor Ray training jobs and restart on failure.

This module provides comprehensive monitoring and auto-restart capabilities
for distributed training jobs on Ray clusters.
"""

import json
import logging
import os
import re
import subprocess
import sys
import threading
import time
from datetime import datetime
from typing import Dict, List, Optional, Tuple, Any, Callable

# Configure logging
logger = logging.getLogger('training_monitor')


def setup_logging(level: Optional[str] = None, log_file: Optional[str] = None) -> None:
    """Configure logging for the training monitor."""
    if level is None:
        level = os.environ.get('TRAINING_MONITOR_LOG_LEVEL', 'INFO')
    
    log_level = getattr(logging, level.upper(), logging.INFO)
    
    handlers = [logging.StreamHandler(sys.stdout)]
    
    file_path = log_file or os.environ.get('TRAINING_MONITOR_LOG_FILE')
    if file_path:
        handlers.append(logging.FileHandler(file_path))
    
    logging.basicConfig(
        level=log_level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=handlers
    )


def run_kubectl_command(head_pod: str, command: List[str], timeout: int = 60) -> Tuple[int, str, str]:
    """
    Execute a kubectl exec command on the Ray head pod.
    
    Args:
        head_pod: Name of the Ray head pod
        command: Command to execute (as list of arguments)
        timeout: Command timeout in seconds
        
    Returns:
        Tuple of (returncode, stdout, stderr)
    """
    kubectl_cmd = [
        'kubectl', 'exec', '-it', head_pod, '--'
    ] + command
    
    try:
        result = subprocess.run(
            kubectl_cmd,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        logger.error(f"Command timed out after {timeout}s: {' '.join(command)}")
        return -1, "", "Command timeout"
    except Exception as e:
        logger.error(f"Failed to execute kubectl command: {e}")
        return -1, "", str(e)


def check_job_status(head_pod: str, job_id: str) -> str:
    """
    Get current status of a Ray job.
    
    Args:
        head_pod: Name of the Ray head pod
        job_id: Ray job ID
        
    Returns:
        Job status: RUNNING, FAILED, SUCCEEDED, PENDING, or UNKNOWN
    """
    returncode, stdout, stderr = run_kubectl_command(
        head_pod, ['ray', 'job', 'status', job_id]
    )
    
    if returncode != 0:
        logger.error(f"Failed to get job status: {stderr}")
        return 'UNKNOWN'
    
    # Parse status from output
    for line in stdout.split('\n'):
        if 'Status' in line or 'status' in line.lower():
            if 'RUNNING' in line.upper():
                return 'RUNNING'
            elif 'FAILED' in line.upper():
                return 'FAILED'
            elif 'SUCCEEDED' in line.upper():
                return 'SUCCEEDED'
            elif 'PENDING' in line.upper():
                return 'PENDING'
    
    # Try alternative: list jobs and find status
    returncode, stdout, stderr = run_kubectl_command(
        head_pod, ['ray', 'job', 'list']
    )
    
    if returncode == 0:
        try:
            jobs = json.loads(stdout)
            for job in jobs:
                if job.get('submission_id') == job_id or job.get('job_id') == job_id:
                    status = job.get('status', 'UNKNOWN').upper()
                    if status in ['RUNNING', 'FAILED', 'SUCCEEDED', 'PENDING']:
                        return status
        except json.JSONDecodeError:
            pass
    
    return 'UNKNOWN'


def get_job_logs(head_pod: str, job_id: str, tail: int = 100) -> str:
    """
    Get logs for a Ray job.
    
    Args:
        head_pod: Name of the Ray head pod
        job_id: Ray job ID
        tail: Number of lines to retrieve from end of log
        
    Returns:
        Job logs as string
    """
    returncode, stdout, stderr = run_kubectl_command(
        head_pod, ['ray', 'job', 'logs', job_id, '--tail', str(tail)]
    )
    
    if returncode != 0:
        logger.error(f"Failed to get job logs: {stderr}")
        return ""
    
    return stdout


def get_current_step(head_pod: str, job_id: str) -> Optional[int]:
    """
    Extract current training step from job logs.
    
    Args:
        head_pod: Name of the Ray head pod
        job_id: Ray job ID
        
    Returns:
        Current step number or None if not found
    """
    logs = get_job_logs(head_pod, job_id, tail=200)
    
    # Try different patterns for step extraction
    patterns = [
        r'step[=:\s]+(\d+)',
        r'global[_\s]?step[=:\s]+(\d+)',
        r'training[_\s]?step[=:\s]+(\d+)',
        r'current[_\s]?step[=:\s]+(\d+)',
        r'\[?step[=:\s]+(\d+)\]?',
        r'iteration[=:\s]+(\d+)',
        r'Epoch\s+\d+[,/\s]+Step\s+(\d+)',
        r'checkpoint[_\s]?step[=:\s]+(\d+)',
    ]
    
    steps = []
    for pattern in patterns:
        matches = re.findall(pattern, logs, re.IGNORECASE)
        for match in matches:
            try:
                step = int(match)
                if step > 0:
                    steps.append(step)
            except ValueError:
                continue
    
    if steps:
        return max(steps)  # Return the highest step found
    
    return None


def get_throughput(head_pod: str, job_id: str) -> Optional[float]:
    """
    Extract training throughput (steps/sec) from job logs.
    
    Args:
        head_pod: Name of the Ray head pod
        job_id: Ray job ID
        
    Returns:
        Throughput in steps/sec or None if not found
    """
    logs = get_job_logs(head_pod, job_id, tail=100)
    
    # Try different patterns for throughput
    patterns = [
        r'throughput[=:\s]+([\d.]+)',
        r'([\d.]+)\s*steps?/sec',
        r'speed[=:\s]+([\d.]+)',
        r'([\d.]+)\s*it/s',
        r'([\d.]+)\s*samples?/sec',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, logs, re.IGNORECASE)
        if match:
            try:
                return float(match.group(1))
            except ValueError:
                continue
    
    return None


class JobMonitor:
    """Monitor a Ray job and track its progress."""
    
    def __init__(self, head_pod: str, job_id: str):
        self.head_pod = head_pod
        self.job_id = job_id
        self.start_time = time.time()
        self.last_step = None
        self.last_step_time = time.time()
        self.step_history: List[Tuple[float, int]] = []
        self.status_history: List[Tuple[float, str]] = []
        
    def update(self) -> Dict[str, Any]:
        """Update monitor state and return current status."""
        current_time = time.time()
        status = check_job_status(self.head_pod, self.job_id)
        self.status_history.append((current_time, status))
        
        # Keep only last 100 status entries
        if len(self.status_history) > 100:
            self.status_history = self.status_history[-100:]
        
        current_step = get_current_step(self.head_pod, self.job_id)
        throughput = get_throughput(self.head_pod, self.job_id)
        
        if current_step is not None and current_step != self.last_step:
            self.last_step = current_step
            self.last_step_time = current_time
            self.step_history.append((current_time, current_step))
            
            # Keep only last 1000 step entries
            if len(self.step_history) > 1000:
                self.step_history = self.step_history[-1000:]
        
        return {
            'status': status,
            'current_step': current_step,
            'throughput': throughput,
            'runtime': current_time - self.start_time,
            'time_since_last_step': current_time - self.last_step_time if self.last_step else None
        }
    
    def is_stalled(self, stagnation_threshold: int = 300) -> bool:
        """Check if job has stalled (no progress)."""
        if self.last_step is None:
            return False  # No steps recorded yet
        
        time_since_last_step = time.time() - self.last_step_time
        return time_since_last_step > stagnation_threshold
    
    def get_progress_summary(self) -> Dict[str, Any]:
        """Get summary of job progress."""
        if len(self.step_history) < 2:
            return {
                'total_steps': self.last_step,
                'avg_throughput': None,
                'eta_seconds': None
            }
        
        # Calculate average throughput
        time_diff = self.step_history[-1][0] - self.step_history[0][0]
        step_diff = self.step_history[-1][1] - self.step_history[0][1]
        
        if time_diff > 0:
            avg_throughput = step_diff / time_diff
        else:
            avg_throughput = None
        
        return {
            'total_steps': self.last_step,
            'avg_throughput': avg_throughput,
            'eta_seconds': None  # Would need target steps to calculate
        }


def monitor_job(
    head_pod: str,
    job_id: str,
    check_interval: int = 30,
    timeout: Optional[int] = None,
    stagnation_threshold: int = 300,
    on_status_change: Optional[Callable[[str, Optional[str]], None]] = None,
    on_stall: Optional[Callable[[], None]] = None
) -> Dict[str, Any]:
    """
    Monitor a specific job until completion or timeout.
    
    Args:
        head_pod: Name of the Ray head pod
        job_id: Ray job ID
        check_interval: Seconds between status checks
        timeout: Maximum seconds to monitor (None for no timeout)
        stagnation_threshold: Seconds without progress to consider stalled
        on_status_change: Callback function(status, old_status) on status change
        on_stall: Callback function() when stall detected
        
    Returns:
        Dict with final status, duration, and final_step
    """
    logger.info(f"Starting to monitor job {job_id} on {head_pod}")
    
    monitor = JobMonitor(head_pod, job_id)
    start_time = time.time()
    last_status = None
    
    while True:
        # Check for timeout
        if timeout and (time.time() - start_time) > timeout:
            logger.warning(f"Monitor timeout reached for job {job_id}")
            return {
                'status': 'TIMEOUT',
                'duration': time.time() - start_time,
                'final_step': monitor.last_step,
                'job_id': job_id
            }
        
        # Update monitor state
        status_info = monitor.update()
        current_status = status_info['status']
        
        # Log status changes
        if current_status != last_status:
            logger.info(f"Job {job_id} status changed: {last_status} -> {current_status}")
            if on_status_change:
                on_status_change(current_status, last_status)
            last_status = current_status
        
        # Log progress periodically
        if status_info['current_step']:
            logger.debug(
                f"Job {job_id}: step={status_info['current_step']}, "
                f"throughput={status_info['throughput']:.2f} steps/sec "
                if status_info['throughput'] else f"Job {job_id}: step={status_info['current_step']}"
            )
        
        # Check for stall
        if monitor.is_stalled(stagnation_threshold):
            logger.warning(f"Job {job_id} appears stalled (no progress for {stagnation_threshold}s)")
            if on_stall:
                on_stall()
            return {
                'status': 'STALLED',
                'duration': time.time() - start_time,
                'final_step': monitor.last_step,
                'job_id': job_id
            }
        
        # Check for completion or failure
        if current_status == 'SUCCEEDED':
            logger.info(f"Job {job_id} completed successfully")
            return {
                'status': 'SUCCEEDED',
                'duration': time.time() - start_time,
                'final_step': monitor.last_step,
                'job_id': job_id
            }
        
        if current_status == 'FAILED':
            logger.error(f"Job {job_id} failed")
            return {
                'status': 'FAILED',
                'duration': time.time() - start_time,
                'final_step': monitor.last_step,
                'job_id': job_id
            }
        
        # Wait before next check
        time.sleep(check_interval)


def detect_stall(
    head_pod: str,
    job_id: str,
    stagnation_threshold: int = 300,
    sample_duration: int = 60
) -> bool:
    """
    Detect if a job has stalled by monitoring it briefly.
    
    Args:
        head_pod: Name of the Ray head pod
        job_id: Ray job ID
        stagnation_threshold: Seconds without progress to consider stalled
        sample_duration: Seconds to monitor before making determination
        
    Returns:
        True if job is stalled
    """
    monitor = JobMonitor(head_pod, job_id)
    
    # Get initial state
    initial_info = monitor.update()
    initial_step = initial_info['current_step']
    
    # Monitor for sample_duration
    logger.debug(f"Monitoring job {job_id} for {sample_duration}s to detect stall")
    time.sleep(sample_duration)
    
    # Check if progress was made
    final_info = monitor.update()
    final_step = final_info['current_step']
    
    if initial_step is None and final_step is None:
        # No steps detected at all - might be stalled or just starting
        return monitor.is_stalled(stagnation_threshold)
    
    if initial_step == final_step:
        # No progress made
        time_since_update = time.time() - monitor.last_step_time
        return time_since_update > stagnation_threshold
    
    return False


def find_latest_checkpoint(checkpoint_dir: str, head_pod: Optional[str] = None) -> Optional[str]:
    """
    Find the latest checkpoint in a directory.
    
    Args:
        checkpoint_dir: Directory containing checkpoints
        head_pod: Optional head pod to search on (for remote directories)
        
    Returns:
        Path to latest checkpoint or None
    """
    if head_pod:
        # Search on remote pod
        returncode, stdout, stderr = run_kubectl_command(
            head_pod, ['ls', '-la', checkpoint_dir]
        )
        
        if returncode != 0:
            logger.error(f"Cannot access checkpoint directory: {stderr}")
            return None
        
        # Parse directory listing
        checkpoints = []
        for line in stdout.split('\n'):
            # Look for step_N directories
            match = re.search(r'step[_-]?(\d+)', line)
            if match:
                step = int(match.group(1))
                # Extract full path from line
                parts = line.split()
                if parts:
                    name = parts[-1]
                    checkpoints.append((step, os.path.join(checkpoint_dir, name)))
        
        if checkpoints:
            checkpoints.sort(key=lambda x: x[0], reverse=True)
            logger.info(f"Found latest checkpoint: {checkpoints[0][1]} (step {checkpoints[0][0]})")
            return checkpoints[0][1]
    else:
        # Search locally
        if not os.path.exists(checkpoint_dir):
            logger.error(f"Checkpoint directory does not exist: {checkpoint_dir}")
            return None
        
        checkpoints = []
        for item in os.listdir(checkpoint_dir):
            item_path = os.path.join(checkpoint_dir, item)
            if os.path.isdir(item_path):
                match = re.search(r'step[_-]?(\d+)', item)
                if match:
                    step = int(match.group(1))
                    checkpoints.append((step, item_path))
        
        if checkpoints:
            checkpoints.sort(key=lambda x: x[0], reverse=True)
            logger.info(f"Found latest checkpoint: {checkpoints[0][1]} (step {checkpoints[0][0]})")
            return checkpoints[0][1]
    
    logger.warning(f"No checkpoints found in {checkpoint_dir}")
    return None


def submit_job_with_resume(
    head_pod: str,
    checkpoint_path: Optional[str],
    config: Dict[str, Any]
) -> str:
    """
    Submit a new job resuming from a checkpoint.
    
    Args:
        head_pod: Name of the Ray head pod
        checkpoint_path: Path to checkpoint directory (or None for fresh start)
        config: Job configuration with 'entrypoint' and optional 'runtime_env'
        
    Returns:
        New job ID
    """
    entrypoint = config.get('entrypoint', '')
    runtime_env = config.get('runtime_env', {})
    
    # Modify entrypoint to include resume flag if checkpoint provided
    if checkpoint_path:
        logger.info(f"Submitting job with resume from: {checkpoint_path}")
        # Add resume flag - common patterns
        resume_flags = [
            f'--resume_from_checkpoint {checkpoint_path}',
            f'--checkpoint_dir {checkpoint_path}',
            f'--resume {checkpoint_path}',
        ]
        
        # Check if entrypoint already has resume flag
        has_resume = any(flag.split()[0] in entrypoint for flag in resume_flags)
        
        if not has_resume:
            # Append first resume flag
            entrypoint = f"{entrypoint} {resume_flags[0]}"
    else:
        logger.info("Submitting fresh job (no checkpoint)")
    
    # Build submission command
    cmd = ['ray', 'job', 'submit', '--entrypoint', entrypoint]
    
    # Add runtime env if provided
    if runtime_env:
        env_json = json.dumps(runtime_env)
        cmd.extend(['--runtime-env', env_json])
    
    # Submit job
    returncode, stdout, stderr = run_kubectl_command(head_pod, cmd, timeout=120)
    
    if returncode != 0:
        raise RuntimeError(f"Failed to submit job: {stderr}")
    
    # Extract job ID from output
    job_id = None
    for line in stdout.split('\n'):
        match = re.search(r'(raysubmit_[a-zA-Z0-9]+)', line)
        if match:
            job_id = match.group(1)
            break
    
    if not job_id:
        raise RuntimeError(f"Could not extract job ID from submission output: {stdout}")
    
    logger.info(f"Submitted job with ID: {job_id}")
    return job_id


def auto_restart(
    head_pod: str,
    job_name: str,
    checkpoint_dir: str,
    max_retries: int = 10,
    retry_delay: int = 60,
    stagnation_threshold: int = 300,
    check_interval: int = 30,
    job_config: Optional[Dict[str, Any]] = None,
    initial_job_id: Optional[str] = None
) -> Dict[str, Any]:
    """
    Main auto-restart loop that monitors a job and restarts on failure.
    
    This function will continuously monitor a training job and automatically
    restart it from the latest checkpoint if it fails or stalls.
    
    Args:
        head_pod: Name of the Ray head pod
        job_name: Name of the training job (for logging)
        checkpoint_dir: Directory containing checkpoints
        max_retries: Maximum number of restart attempts
        retry_delay: Seconds to wait between retries
        stagnation_threshold: Seconds without progress to consider stalled
        check_interval: Seconds between status checks
        job_config: Job configuration for restarts (required if no initial_job_id)
        initial_job_id: Optional existing job ID to monitor
        
    Returns:
        Dict with final status:
        - success: bool
        - final_step: int or None
        - total_retries: int
        - reason: str (why monitoring ended)
        - job_id: final job ID
    """
    logger.info(f"Starting auto-restart monitor for job '{job_name}'")
    logger.info(f"Checkpoint directory: {checkpoint_dir}")
    logger.info(f"Max retries: {max_retries}")
    
    if not initial_job_id and not job_config:
        raise ValueError("Either initial_job_id or job_config must be provided")
    
    retry_count = 0
    current_job_id = initial_job_id
    final_step = None
    
    # If no initial job, submit one
    if not current_job_id:
        if not job_config:
            raise ValueError("job_config is required when no initial_job_id is provided")
        checkpoint_path = find_latest_checkpoint(checkpoint_dir, head_pod)
        current_job_id = submit_job_with_resume(
            head_pod=head_pod,
            checkpoint_path=checkpoint_path,
            config=job_config
        )
    
    while retry_count < max_retries:
        logger.info(f"Monitoring job {current_job_id} (attempt {retry_count + 1}/{max_retries})")
        
        # Monitor the job
        result = monitor_job(
            head_pod=head_pod,
            job_id=current_job_id,
            check_interval=check_interval,
            timeout=None,
            stagnation_threshold=stagnation_threshold
        )
        
        final_step = result.get('final_step')
        status = result['status']
        
        if status == 'SUCCEEDED':
            logger.info(f"Job '{job_name}' completed successfully!")
            return {
                'success': True,
                'final_step': final_step,
                'total_retries': retry_count,
                'reason': 'completed',
                'job_id': current_job_id
            }
        
        # Job failed or stalled - need to restart
        retry_count += 1
        
        if retry_count >= max_retries:
            logger.error(f"Max retries ({max_retries}) reached. Giving up.")
            return {
                'success': False,
                'final_step': final_step,
                'total_retries': retry_count,
                'reason': f'max_retries_reached after {status}',
                'job_id': current_job_id
            }
        
        logger.warning(
            f"Job {current_job_id} {status}. "
            f"Restarting in {retry_delay}s (attempt {retry_count + 1}/{max_retries})"
        )
        
        # Wait before restart
        time.sleep(retry_delay)
        
        # Find latest checkpoint
        checkpoint_path = find_latest_checkpoint(checkpoint_dir, head_pod)
        
        if not checkpoint_path:
            logger.error("No checkpoint found for restart!")
            return {
                'success': False,
                'final_step': final_step,
                'total_retries': retry_count,
                'reason': 'no_checkpoint_found',
                'job_id': current_job_id
            }
        
        # Submit new job with resume
        try:
            config = job_config if job_config is not None else {'entrypoint': 'python train.py'}
            current_job_id = submit_job_with_resume(
                head_pod=head_pod,
                checkpoint_path=checkpoint_path,
                config=config
            )
        except Exception as e:
            logger.error(f"Failed to restart job: {e}")
            return {
                'success': False,
                'final_step': final_step,
                'total_retries': retry_count,
                'reason': f'restart_failed: {str(e)}',
                'job_id': current_job_id
            }
    
    # Should not reach here
    return {
        'success': False,
        'final_step': final_step,
        'total_retries': retry_count,
        'reason': 'unexpected_exit',
        'job_id': current_job_id
    }


def check_gpu_utilization(head_pod: str, namespace: str = "default") -> Dict[str, Any]:
    """
    Check GPU utilization on the Ray head pod using nvidia-smi.
    
    Args:
        head_pod: Name of the Ray head pod
        namespace: Kubernetes namespace
        
    Returns:
        Dictionary with GPU utilization information:
        {
            'gpu_count': int,
            'gpu_utilizations': List[float],  # Percentage for each GPU
            'memory_used': List[int],         # MB for each GPU
            'memory_total': List[int],        # MB for each GPU
            'processes': List[Dict],          # Running processes
            'healthy': bool
        }
    """
    try:
        # Run nvidia-smi to get GPU utilization
        returncode, stdout, stderr = run_kubectl_command(
            head_pod,
            ['nvidia-smi', '--query-gpu=utilization.gpu,memory.used,memory.total', 
             '--format=csv,noheader,nounits'],
            timeout=10
        )
        
        if returncode != 0:
            return {
                'gpu_count': 0,
                'gpu_utilizations': [],
                'memory_used': [],
                'memory_total': [],
                'processes': [],
                'healthy': False,
                'error': f'nvidia-smi failed: {stderr}'
            }
        
        # Parse GPU utilization
        gpu_utils = []
        memory_used = []
        memory_total = []
        
        for line in stdout.strip().split('\n'):
            if ',' in line:
                parts = line.split(',')
                if len(parts) >= 3:
                    gpu_utils.append(float(parts[0].strip()))
                    memory_used.append(int(parts[1].strip()))
                    memory_total.append(int(parts[2].strip()))
        
        # Get process info
        returncode2, stdout2, _ = run_kubectl_command(
            head_pod,
            ['nvidia-smi', '--query-compute-apps=pid,process_name,gpu_name,used_memory',
             '--format=csv,noheader'],
            timeout=10
        )
        
        processes = []
        if returncode2 == 0:
            for line in stdout2.strip().split('\n'):
                if ',' in line:
                    parts = line.split(',')
                    if len(parts) >= 4:
                        processes.append({
                            'pid': parts[0].strip(),
                            'name': parts[1].strip(),
                            'gpu': parts[2].strip(),
                            'memory': parts[3].strip()
                        })
        
        # Determine if healthy (GPUs should be utilized if training is running)
        avg_util = sum(gpu_utils) / len(gpu_utils) if gpu_utils else 0
        
        return {
            'gpu_count': len(gpu_utils),
            'gpu_utilizations': gpu_utils,
            'memory_used': memory_used,
            'memory_total': memory_total,
            'processes': processes,
            'healthy': True,
            'avg_utilization': avg_util
        }
        
    except Exception as e:
        return {
            'gpu_count': 0,
            'gpu_utilizations': [],
            'memory_used': [],
            'memory_total': [],
            'processes': [],
            'healthy': False,
            'error': str(e)
        }


def verify_ray_resources(head_pod: str, namespace: str = "default") -> Dict[str, Any]:
    """
    Verify Ray cluster resources using ray status.
    
    Args:
        head_pod: Name of the Ray head pod
        namespace: Kubernetes namespace
        
    Returns:
        Dictionary with resource information:
        {
            'gpus_available': float,
            'gpus_used': float,
            'cpus_available': float,
            'cpus_used': float,
            'healthy': bool
        }
    """
    try:
        returncode, stdout, stderr = run_kubectl_command(
            head_pod,
            ['ray', 'status'],
            timeout=10
        )
        
        if returncode != 0:
            return {
                'gpus_available': 0,
                'gpus_used': 0,
                'cpus_available': 0,
                'cpus_used': 0,
                'healthy': False,
                'error': f'ray status failed: {stderr}'
            }
        
        gpus_available = 0.0
        gpus_used = 0.0
        cpus_available = 0.0
        cpus_used = 0.0
        
        for line in stdout.split('\n'):
            # Parse GPU line: " 4.0/4.0 GPU (4.0 used of 4.0 reserved)"
            if 'GPU' in line and '/' in line:
                match = re.search(r'(\d+\.?\d*)/(\d+\.?\d*)\s+GPU', line)
                if match:
                    gpus_used = float(match.group(1))
                    gpus_available = float(match.group(2))
            
            # Parse CPU line: " 5.0/16.0 CPU"
            if 'CPU' in line and '/' in line and 'GPU' not in line:
                match = re.search(r'(\d+\.?\d*)/(\d+\.?\d*)\s+CPU', line)
                if match:
                    cpus_used = float(match.group(1))
                    cpus_available = float(match.group(2))
        
        return {
            'gpus_available': gpus_available,
            'gpus_used': gpus_used,
            'cpus_available': cpus_available,
            'cpus_used': cpus_used,
            'healthy': True
        }
        
    except Exception as e:
        return {
            'gpus_available': 0,
            'gpus_used': 0,
            'cpus_available': 0,
            'cpus_used': 0,
            'healthy': False,
            'error': str(e)
        }


def check_efa_utilization(head_pod: str, namespace: str = "default") -> Dict[str, Any]:
    """
    Check if NCCL is using EFA (OFI) or falling back to TCP sockets.
    
    Examines NCCL initialization logs in Ray worker output to determine
    the actual transport being used.
    
    Args:
        head_pod: Name of the Ray head pod
        namespace: Kubernetes namespace
        
    Returns:
        Dictionary with EFA status:
        {
            'efa_active': bool,      # True if NCCL is using EFA/OFI
            'transport': str,        # 'ofi' or 'socket'
            'details': str           # Relevant log lines
        }
    """
    try:
        returncode, stdout, stderr = run_kubectl_command(
            head_pod,
            ['bash', '-c', 
             "grep -i 'NET/OFI\\|NET/Socket' /tmp/ray/session_latest/logs/worker*.out 2>/dev/null | head -10"],
            timeout=10
        )
        
        if returncode != 0 or not stdout.strip():
            return {
                'efa_active': False,
                'transport': 'unknown',
                'details': 'No NCCL transport logs found. Training may not have initialized NCCL yet.'
            }
        
        if 'NET/OFI' in stdout:
            return {
                'efa_active': True,
                'transport': 'ofi',
                'details': stdout.strip()
            }
        elif 'NET/Socket' in stdout:
            return {
                'efa_active': False,
                'transport': 'socket',
                'details': stdout.strip()
            }
        else:
            return {
                'efa_active': False,
                'transport': 'unknown',
                'details': stdout.strip()
            }
            
    except Exception as e:
        return {
            'efa_active': False,
            'transport': 'unknown',
            'details': f'Error checking EFA: {str(e)}'
        }


def get_training_health(
    head_pod: str,
    checkpoint_dir: str,
    all_pods: Optional[List[str]] = None,
    namespace: str = "default"
) -> Dict[str, Any]:
    """
    Get a comprehensive training health report in a single call.
    
    Combines GPU utilization, EFA status, checkpoint progress, and Ray
    resource allocation into one report. Use this instead of running
    multiple ad-hoc kubectl commands.
    
    Args:
        head_pod: Name of the Ray head pod
        checkpoint_dir: Path to checkpoint directory in the pod
        all_pods: List of all pod names (head + workers). If None, only checks head.
        namespace: Kubernetes namespace
        
    Returns:
        Dictionary with full health report:
        {
            'healthy': bool,
            'gpu': {
                'total_gpus': int,
                'avg_utilization': float,
                'per_node': [{'pod': str, 'util': float, 'mem_used': int, 'mem_total': int}]
            },
            'efa': {
                'active': bool,
                'transport': str,
                'channels': str
            },
            'checkpoints': {
                'latest_step': int,
                'checkpoint_count': int,
                'checkpoint_dir': str
            },
            'ray': {
                'gpus_used': float,
                'gpus_available': float,
                'cpus_used': float,
                'cpus_available': float
            },
            'issues': [str]   # List of detected problems
        }
    """
    report = {
        'healthy': True,
        'gpu': {'total_gpus': 0, 'avg_utilization': 0.0, 'per_node': []},
        'efa': {'active': False, 'transport': 'unknown', 'channels': ''},
        'checkpoints': {'latest_step': 0, 'checkpoint_count': 0, 'checkpoint_dir': checkpoint_dir},
        'ray': {'gpus_used': 0, 'gpus_available': 0, 'cpus_used': 0, 'cpus_available': 0},
        'issues': []
    }
    
    pods_to_check = all_pods if all_pods else [head_pod]
    
    # --- GPU Utilization ---
    gpu_utils = []
    for pod in pods_to_check:
        try:
            returncode, stdout, _ = run_kubectl_command(
                pod,
                ['nvidia-smi', '--query-gpu=utilization.gpu,memory.used,memory.total',
                 '--format=csv,noheader,nounits'],
                timeout=10
            )
            if returncode == 0 and stdout.strip():
                for line in stdout.strip().split('\n'):
                    parts = line.split(',')
                    if len(parts) >= 3:
                        util = float(parts[0].strip())
                        mem_used = int(parts[1].strip())
                        mem_total = int(parts[2].strip())
                        gpu_utils.append(util)
                        report['gpu']['per_node'].append({
                            'pod': pod.split('-')[-1] if '-' in pod else pod,
                            'util': util,
                            'mem_used': mem_used,
                            'mem_total': mem_total
                        })
        except Exception:
            pass
    
    if gpu_utils:
        report['gpu']['total_gpus'] = len(gpu_utils)
        report['gpu']['avg_utilization'] = sum(gpu_utils) / len(gpu_utils)
        if report['gpu']['avg_utilization'] < 5.0:
            report['issues'].append('GPU utilization < 5% -- training may not be running')
            report['healthy'] = False
    else:
        report['issues'].append('Could not read GPU utilization from any node')
        report['healthy'] = False
    
    # --- EFA Status ---
    try:
        returncode, stdout, _ = run_kubectl_command(
            head_pod,
            ['bash', '-c',
             "grep -E 'NET/OFI|NET/Socket|via NET/' /tmp/ray/session_latest/logs/worker*.out 2>/dev/null | tail -15"],
            timeout=10
        )
        if returncode == 0 and stdout.strip():
            if 'NET/OFI' in stdout:
                report['efa']['active'] = True
                report['efa']['transport'] = 'ofi (EFA)'
                # Extract channel info
                channels = [l.strip() for l in stdout.split('\n') if 'via NET/OFI' in l]
                report['efa']['channels'] = f"{len(channels)} channels via NET/OFI"
            elif 'NET/Socket' in stdout:
                report['efa']['transport'] = 'socket (TCP fallback)'
                report['issues'].append('EFA not active -- NCCL using TCP sockets. Set NCCL_NET=ofi')
            else:
                report['efa']['transport'] = 'unknown'
        else:
            report['efa']['transport'] = 'no NCCL logs yet'
    except Exception:
        pass
    
    # --- Checkpoint Progress ---
    try:
        returncode, stdout, _ = run_kubectl_command(
            head_pod,
            ['bash', '-c', f'ls -1 {checkpoint_dir} 2>/dev/null | grep global_step | sort -V'],
            timeout=10
        )
        if returncode == 0 and stdout.strip():
            steps = []
            for line in stdout.strip().split('\n'):
                if line.startswith('global_step_'):
                    try:
                        steps.append(int(line.replace('global_step_', '')))
                    except ValueError:
                        pass
            if steps:
                report['checkpoints']['latest_step'] = max(steps)
                report['checkpoints']['checkpoint_count'] = len(steps)
    except Exception:
        pass
    
    # --- Ray Resources ---
    try:
        returncode, stdout, _ = run_kubectl_command(
            head_pod,
            ['ray', 'status'],
            timeout=10
        )
        if returncode == 0:
            for line in stdout.split('\n'):
                if 'GPU' in line and '/' in line:
                    match = re.search(r'(\d+\.?\d*)/(\d+\.?\d*)\s+GPU', line)
                    if match:
                        report['ray']['gpus_used'] = float(match.group(1))
                        report['ray']['gpus_available'] = float(match.group(2))
                if 'CPU' in line and '/' in line and 'GPU' not in line:
                    match = re.search(r'(\d+\.?\d*)/(\d+\.?\d*)\s+CPU', line)
                    if match:
                        report['ray']['cpus_used'] = float(match.group(1))
                        report['ray']['cpus_available'] = float(match.group(2))
            
            if report['ray']['gpus_available'] > 0 and report['ray']['gpus_used'] == 0:
                report['issues'].append('Ray has GPUs available but none allocated')
                report['healthy'] = False
    except Exception:
        pass
    
    return report


def print_training_health(report: Dict[str, Any]) -> None:
    """Pretty-print a training health report to stdout."""
    status = "HEALTHY" if report['healthy'] else "UNHEALTHY"
    print(f"\n{'='*60}")
    print(f"  Training Health: {status}")
    print(f"{'='*60}")
    
    # GPU
    print(f"\n  GPU Utilization (avg: {report['gpu']['avg_utilization']:.0f}%)")
    for node in report['gpu']['per_node']:
        bar = '#' * int(node['util'] / 5) + '.' * (20 - int(node['util'] / 5))
        print(f"    {node['pod']:>10}: [{bar}] {node['util']:.0f}%  {node['mem_used']}/{node['mem_total']} MiB")
    
    # EFA
    efa = report['efa']
    efa_icon = "OK" if efa['active'] else "!!"
    print(f"\n  EFA: [{efa_icon}] {efa['transport']}  {efa.get('channels', '')}")
    
    # Checkpoints
    ckpt = report['checkpoints']
    print(f"\n  Checkpoints: step {ckpt['latest_step']} ({ckpt['checkpoint_count']} saved)")
    
    # Ray
    ray = report['ray']
    print(f"  Ray: {ray['gpus_used']}/{ray['gpus_available']} GPU, {ray['cpus_used']}/{ray['cpus_available']} CPU")
    
    # Issues
    if report['issues']:
        print(f"\n  Issues:")
        for issue in report['issues']:
            print(f"    - {issue}")
    
    print(f"{'='*60}\n")


def start_background_monitor(
    head_pod: str,
    job_id: str,
    check_interval: int = 30,
    callback: Optional[Callable[[Dict[str, Any]], None]] = None
) -> threading.Thread:
    """
    Start monitoring a job in a background thread.
    
    Args:
        head_pod: Name of the Ray head pod
        job_id: Ray job ID
        check_interval: Seconds between status checks
        callback: Optional callback(result_dict) when monitoring ends
        
    Returns:
        Thread object (already started)
    """
    def monitor_wrapper():
        result = monitor_job(head_pod, job_id, check_interval)
        if callback:
            callback(result)
    
    thread = threading.Thread(target=monitor_wrapper, daemon=True)
    thread.start()
    logger.info(f"Started background monitor for job {job_id}")
    return thread


# Convenience functions for CLI usage

def main():
    """CLI entry point for the training monitor."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Monitor Ray training jobs')
    parser.add_argument('--head-pod', required=True, help='Ray head pod name')
    parser.add_argument('--job-id', help='Job ID to monitor')
    parser.add_argument('--job-name', help='Job name for auto-restart')
    parser.add_argument('--checkpoint-dir', help='Checkpoint directory')
    parser.add_argument('--auto-restart', action='store_true', help='Enable auto-restart')
    parser.add_argument('--max-retries', type=int, default=10, help='Max retry attempts')
    parser.add_argument('--retry-delay', type=int, default=60, help='Seconds between retries')
    parser.add_argument('--check-interval', type=int, default=30, help='Seconds between checks')
    parser.add_argument('--stagnation-threshold', type=int, default=300, help='Stall detection threshold')
    parser.add_argument('--log-level', default='INFO', help='Logging level')
    parser.add_argument('--log-file', help='Log file path')
    
    args = parser.parse_args()
    
    # Setup logging
    setup_logging(args.log_level, args.log_file)
    
    if args.auto_restart:
        if not args.job_name or not args.checkpoint_dir:
            parser.error('--job-name and --checkpoint-dir required for auto-restart')
        
        result = auto_restart(
            head_pod=args.head_pod,
            job_name=args.job_name,
            checkpoint_dir=args.checkpoint_dir,
            max_retries=args.max_retries,
            retry_delay=args.retry_delay,
            stagnation_threshold=args.stagnation_threshold,
            check_interval=args.check_interval,
            initial_job_id=args.job_id
        )
        
        print(f"\nAuto-restart result:")
        print(f"  Success: {result['success']}")
        print(f"  Final step: {result['final_step']}")
        print(f"  Total retries: {result['total_retries']}")
        print(f"  Reason: {result['reason']}")
        
        sys.exit(0 if result['success'] else 1)
    
    elif args.job_id:
        result = monitor_job(
            head_pod=args.head_pod,
            job_id=args.job_id,
            check_interval=args.check_interval,
            stagnation_threshold=args.stagnation_threshold
        )
        
        print(f"\nMonitoring result:")
        print(f"  Status: {result['status']}")
        print(f"  Duration: {result['duration']:.1f}s")
        print(f"  Final step: {result['final_step']}")
        
        sys.exit(0 if result['status'] == 'SUCCEEDED' else 1)
    
    else:
        parser.error('Either --job-id or --auto-restart required')


if __name__ == '__main__':
    main()
