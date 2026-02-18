# Training Monitor Skill

Automatically monitor Ray training jobs and restart on failure with checkpoint recovery.

## Overview

This skill provides comprehensive monitoring and auto-restart capabilities for distributed training jobs on Ray clusters. It tracks job status, detects failures and stalls, and automatically restarts jobs from the latest checkpoint.

## Features

- **Real-time Monitoring**: Track job status (RUNNING/FAILED/SUCCEEDED/PENDING)
- **Progress Tracking**: Extract current step and throughput from logs
- **Stall Detection**: Identify jobs with no progress
- **Auto-restart**: Automatically restart failed jobs from checkpoints
- **Retry Logic**: Configurable retry limits with exponential backoff
- **Comprehensive Logging**: All activity logged with timestamps
- **GPU Monitoring**: Track GPU utilization and detect when GPUs are not being used

## ⚠️ Important Warnings

### Do NOT Monitor Jobs Started with `ray job submit`

**Problem**: If training was started using `ray job submit`, the job runs in an isolated environment and cannot access the Ray cluster's GPU resources. The monitor will show the job as "RUNNING" but GPUs will show 0% utilization.

**Symptoms**:
- Job status shows RUNNING
- `check_gpu_utilization()` returns 0% for all GPUs
- `verify_ray_resources()` shows GPUs available but 0 used
- Training makes no progress

**Solution**: Start training directly in the head pod using `kubectl exec`:

```bash
# ❌ WRONG - Job will run but can't access GPUs
ray job submit --working-dir /workspace -- python3 train.py

# ✅ CORRECT - Training runs in pod with full GPU access
kubectl exec <head-pod> -- bash -c 'cd /workspace && python3 train.py'
```

**Verification**: Always verify GPU utilization after starting training:

```python
from training_monitor.src.monitor import check_gpu_utilization, verify_ray_resources

# Check GPU utilization
gpu_info = check_gpu_utilization('head-pod-name')
print(f"GPU utilization: {gpu_info['avg_utilization']}%")

# Check Ray resources
resources = verify_ray_resources('head-pod-name')
print(f"GPUs used: {resources['gpus_used']}/{resources['gpus_available']}")
```

### Verify EFA is Being Used (Not Just Present)

**Problem**: An EFA device being present and ACTIVE does **not** mean NCCL is using it. NCCL can silently fall back to TCP sockets, causing NCCL timeout errors (ALLGATHER timeouts) during distributed training.

**How to check**:
```bash
# Look in NCCL logs for transport type
kubectl exec <head-pod> -- grep -i 'NET/OFI\|NET/Socket' /tmp/ray/session_latest/logs/worker*.out
```

- `NET/OFI Selected provider is efa` = EFA is working
- `NET/Socket` or no output = Fallen back to TCP

**Fix**: Ensure `NCCL_NET=ofi` and `LD_LIBRARY_PATH` includes `/opt/amazon/ofi-nccl/lib/x86_64-linux-gnu` in pod environment variables.

```python
from training_monitor.src.monitor import check_efa_utilization

efa = check_efa_utilization('head-pod-name')
if not efa['efa_active']:
    print(f"WARNING: EFA not active! Transport: {efa['transport']}")
```

## Installation

The skill is self-contained. Just import and use:

```python
from training_monitor.src.monitor import auto_restart
```

## Quick Start

### Full Training Health Report

One call to get GPU utilization, EFA status, checkpoint progress, and Ray resources:

```python
from training_monitor.src.monitor import get_training_health, print_training_health

report = get_training_health(
    head_pod='verl-grpo-training-head-pgbtb',
    checkpoint_dir='/checkpoints/GRPO/verl-grpo-training-500',
    all_pods=[
        'verl-grpo-training-head-pgbtb',
        'verl-grpo-training-worker-worker-group-8v7pg',
        'verl-grpo-training-worker-worker-group-nqvvq',
        'verl-grpo-training-worker-worker-group-v5rz4',
    ]
)

# Pretty-print the report
print_training_health(report)

# Or access fields directly
print(f"Healthy: {report['healthy']}")
print(f"GPU avg: {report['gpu']['avg_utilization']:.0f}%")
print(f"EFA: {report['efa']['transport']}")
print(f"Latest checkpoint: step {report['checkpoints']['latest_step']}")
print(f"Issues: {report['issues']}")
```

### Basic Auto-Restart

```python
from training_monitor.src.monitor import auto_restart

# Start monitoring with auto-restart
auto_restart(
    head_pod='training-head-xxxxx',
    job_name='my-training',
    checkpoint_dir='/checkpoints/GRPO/my-training',
    max_retries=10,
    retry_delay=60
)
```

### Monitor a Specific Job

```python
from training_monitor.src.monitor import monitor_job

# Monitor an existing job
monitor_job(
    head_pod='training-head-xxxxx',
    job_id='raysubmit_abc123',
    check_interval=30
)
```

### Check Job Status

```python
from training_monitor.src.monitor import check_job_status

status = check_job_status('training-head-xxxxx', 'raysubmit_abc123')
print(f"Job status: {status}")  # RUNNING, FAILED, SUCCEEDED, PENDING, UNKNOWN
```

### Get Current Training Step

```python
from training_monitor.src.monitor import get_current_step

step = get_current_step('training-head-xxxxx', 'raysubmit_abc123')
print(f"Current step: {step}")
```

### Detect Stalled Jobs

```python
from training_monitor.src.monitor import detect_stall

is_stalled = detect_stall(
    head_pod='training-head-xxxxx',
    job_id='raysubmit_abc123',
    stagnation_threshold=300  # 5 minutes
)
```

### Submit Job with Resume

```python
from training_monitor.src.monitor import submit_job_with_resume

job_id = submit_job_with_resume(
    head_pod='training-head-xxxxx',
    checkpoint_path='/checkpoints/GRPO/my-training/step_1000',
    config={
        'entrypoint': 'python train.py',
        'runtime_env': {'working_dir': '/app'}
    }
)
```

## API Reference

### `auto_restart(head_pod, job_name, checkpoint_dir, max_retries=10, retry_delay=60, stagnation_threshold=300, check_interval=30)`

Main auto-restart loop that monitors a job and restarts on failure.

**Parameters:**
- `head_pod` (str): Name of the Ray head pod
- `job_name` (str): Name of the training job
- `checkpoint_dir` (str): Directory containing checkpoints
- `max_retries` (int): Maximum number of restart attempts
- `retry_delay` (int): Seconds to wait between retries
- `stagnation_threshold` (int): Seconds without progress to consider stalled
- `check_interval` (int): Seconds between status checks

**Returns:**
- `dict`: Final status with fields: `success`, `final_step`, `total_retries`, `reason`

### `monitor_job(head_pod, job_id, check_interval=30, timeout=None)`

Monitor a specific job until completion or timeout.

**Parameters:**
- `head_pod` (str): Name of the Ray head pod
- `job_id` (str): Ray job ID
- `check_interval` (int): Seconds between checks
- `timeout` (int): Maximum seconds to monitor (None for no timeout)

**Returns:**
- `dict`: Final status with fields: `status`, `duration`, `final_step`

### `check_job_status(head_pod, job_id)`

Get current status of a Ray job.

**Parameters:**
- `head_pod` (str): Name of the Ray head pod
- `job_id` (str): Ray job ID

**Returns:**
- `str`: One of RUNNING, FAILED, SUCCEEDED, PENDING, UNKNOWN

### `get_current_step(head_pod, job_id)`

Extract current training step from job logs.

**Parameters:**
- `head_pod` (str): Name of the Ray head pod
- `job_id` (str): Ray job ID

**Returns:**
- `int` or `None`: Current step number or None if not found

### `detect_stall(head_pod, job_id, stagnation_threshold=300)`

Detect if a job has stalled (no progress).

**Parameters:**
- `head_pod` (str): Name of the Ray head pod
- `job_id` (str): Ray job ID
- `stagnation_threshold` (int): Seconds without progress to consider stalled

**Returns:**
- `bool`: True if job is stalled

### `submit_job_with_resume(head_pod, checkpoint_path, config)`

Submit a new job resuming from a checkpoint.

**Parameters:**
- `head_pod` (str): Name of the Ray head pod
- `checkpoint_path` (str): Path to checkpoint directory
- `config` (dict): Job configuration with 'entrypoint' and optional 'runtime_env'

**Returns:**
- `str`: New job ID

### `check_gpu_utilization(head_pod, namespace='default')`

Check GPU utilization on the Ray head pod using nvidia-smi.

**Parameters:**
- `head_pod` (str): Name of the Ray head pod
- `namespace` (str): Kubernetes namespace (default: 'default')

**Returns:**
- `dict`: GPU information with keys:
  - `gpu_count`: Number of GPUs detected
  - `gpu_utilizations`: List of utilization percentages
  - `memory_used`: List of memory used (MB)
  - `memory_total`: List of total memory (MB)
  - `processes`: List of running GPU processes
  - `avg_utilization`: Average utilization across all GPUs
  - `healthy`: Boolean indicating if check succeeded

**Example:**
```python
from training_monitor.src.monitor import check_gpu_utilization

gpu_info = check_gpu_utilization('head-pod-name')
if gpu_info['healthy']:
    print(f"GPUs: {gpu_info['gpu_count']}")
    print(f"Average utilization: {gpu_info['avg_utilization']:.1f}%")
    for i, util in enumerate(gpu_info['gpu_utilizations']):
        print(f"  GPU {i}: {util}%")
```

### `verify_ray_resources(head_pod, namespace='default')`

Verify Ray cluster resources using `ray status`.

**Parameters:**
- `head_pod` (str): Name of the Ray head pod
- `namespace` (str): Kubernetes namespace (default: 'default')

**Returns:**
- `dict`: Resource information with keys:
  - `gpus_available`: Total GPUs in cluster
  - `gpus_used`: GPUs currently allocated
  - `cpus_available`: Total CPUs in cluster
  - `cpus_used`: CPUs currently allocated
  - `healthy`: Boolean indicating if check succeeded

**Example:**
```python
from training_monitor.src.monitor import verify_ray_resources

resources = verify_ray_resources('head-pod-name')
if resources['healthy']:
    print(f"GPUs: {resources['gpus_used']}/{resources['gpus_available']}")
    if resources['gpus_used'] == 0 and resources['gpus_available'] > 0:
        print("WARNING: GPUs available but not being used!")
```

## Configuration

### Environment Variables

- `TRAINING_MONITOR_LOG_LEVEL`: Logging level (DEBUG, INFO, WARNING, ERROR)
- `TRAINING_MONITOR_LOG_FILE`: Path to log file (default: stdout)

### Checkpoint Directory Structure

The monitor expects checkpoints in this structure:
```
checkpoint_dir/
├── step_100/
├── step_500/
├── step_1000/
└── latest -> step_1000/
```

## Examples

### Example 1: Full Training Pipeline

```python
from training_monitor.src.monitor import auto_restart
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)

# Run training with auto-restart
result = auto_restart(
    head_pod='training-head-abc123',
    job_name='grpo-training',
    checkpoint_dir='/checkpoints/GRPO/grpo-training',
    max_retries=10,
    retry_delay=60,
    stagnation_threshold=600,  # 10 minutes
    check_interval=30
)

if result['success']:
    print(f"Training completed at step {result['final_step']}")
else:
    print(f"Training failed after {result['total_retries']} retries: {result['reason']}")
```

### Example 2: Background Monitoring

```python
from training_monitor.src.monitor import monitor_job
import threading

def monitor_in_background(head_pod, job_id):
    result = monitor_job(head_pod, job_id, check_interval=30)
    print(f"Job {job_id} finished with status: {result['status']}")

# Start monitoring in background
thread = threading.Thread(
    target=monitor_in_background,
    args=('training-head-abc123', 'raysubmit_xyz789')
)
thread.daemon = True
thread.start()
```

### Example 3: Custom Restart Logic

```python
from training_monitor.src.monitor import check_job_status, submit_job_with_resume
import time

head_pod = 'training-head-abc123'
job_id = 'raysubmit_initial123'
retry_count = 0
max_retries = 5

while retry_count < max_retries:
    status = check_job_status(head_pod, job_id)
    
    if status == 'SUCCEEDED':
        print("Training completed successfully!")
        break
    elif status == 'FAILED':
        print(f"Job failed, attempt {retry_count + 1}/{max_retries}")
        
        # Custom logic to find latest checkpoint
        checkpoint_path = find_latest_checkpoint('/checkpoints/my-job')
        
        # Submit new job
        job_id = submit_job_with_resume(
            head_pod=head_pod,
            checkpoint_path=checkpoint_path,
            config={'entrypoint': 'python train.py --resume'}
        )
        retry_count += 1
        time.sleep(60)
    else:
        time.sleep(30)
```

## Troubleshooting

### Job Not Found

If you get "Job not found" errors:
- Verify the head pod name is correct
- Check that the job ID exists: `kubectl exec -it <head_pod> -- ray job list`

### Checkpoint Not Found

If auto-restart fails to find checkpoints:
- Verify checkpoint_dir path is correct
- Ensure checkpoints are being saved in the expected format
- Check permissions on the checkpoint directory

### Permission Denied

If you get permission errors:
- Ensure kubectl is configured correctly
- Verify you have access to the Ray cluster namespace

## Dependencies

- Python 3.7+
- kubectl (configured for your cluster)
- Ray cluster (with job submission API enabled)

No Python package dependencies required - uses only standard library.
