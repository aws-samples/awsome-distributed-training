#!/usr/bin/env python3
"""
Claude Code Command: Monitor Training Jobs

This command wraps the training-monitor skill to provide easy monitoring
of distributed training jobs on Ray clusters.

Examples:
    # Monitor a job with auto-restart
    /monitor_training --head-pod training-head-xxxxx --job-name my-training --checkpoint-dir /checkpoints/GRPO/my-training

    # Check job status
    /monitor_training --head-pod training-head-xxxxx --job-id raysubmit_abc123 --action status

    # Get current training step
    /monitor_training --head-pod training-head-xxxxx --job-id raysubmit_abc123 --action step

    # Check GPU utilization
    /monitor_training --head-pod training-head-xxxxx --action gpu

    # Watch job logs
    /monitor_training --head-pod training-head-xxxxx --job-id raysubmit_abc123 --action logs
"""

import argparse
import subprocess
import sys
import json
from pathlib import Path

# Add the skill src/ directory to path so we can import monitor.py directly
SKILL_SRC_PATH = Path(__file__).parent.parent / "opencode" / "skills" / "training-monitor" / "src"
sys.path.insert(0, str(SKILL_SRC_PATH))


def run_skill_function(function_name: str, *args, **kwargs):
    """Run a function from the training-monitor skill."""
    try:
        from monitor import (
            auto_restart, monitor_job, check_job_status, get_current_step,
            detect_stall, check_gpu_utilization, verify_ray_resources,
            get_training_health, print_training_health, check_efa_utilization
        )
        
        functions = {
            'auto_restart': auto_restart,
            'monitor_job': monitor_job,
            'check_job_status': check_job_status,
            'get_current_step': get_current_step,
            'detect_stall': detect_stall,
            'check_gpu_utilization': check_gpu_utilization,
            'verify_ray_resources': verify_ray_resources,
            'get_training_health': get_training_health,
            'print_training_health': print_training_health,
            'check_efa_utilization': check_efa_utilization,
        }
        
        if function_name not in functions:
            return {'error': f'Unknown function: {function_name}'}
        
        result = functions[function_name](*args, **kwargs)
        return result
    except Exception as e:
        return {'error': str(e)}


def watch_logs(head_pod: str, job_id: str, follow: bool = True):
    """Watch job logs using kubectl."""
    cmd = ['kubectl', 'exec', '-it', head_pod, '--', 'ray', 'job', 'logs', job_id]
    if follow:
        cmd.append('-f')
    
    try:
        subprocess.run(cmd)
        return {'success': True, 'message': 'Log streaming completed'}
    except KeyboardInterrupt:
        return {'success': True, 'message': 'Log streaming stopped by user'}
    except Exception as e:
        return {'error': str(e)}


def main():
    parser = argparse.ArgumentParser(
        description='Monitor Ray training jobs',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Auto-restart monitoring with checkpoint recovery
  %(prog)s --head-pod training-head-xxxxx --job-name my-training --checkpoint-dir /checkpoints/GRPO/my-training

  # Check job status
  %(prog)s --head-pod training-head-xxxxx --job-id raysubmit_abc123 --action status

  # Get current training step
  %(prog)s --head-pod training-head-xxxxx --job-id raysubmit_abc123 --action step

  # Check GPU utilization
  %(prog)s --head-pod training-head-xxxxx --action gpu

  # Watch job logs (follow mode)
  %(prog)s --head-pod training-head-xxxxx --job-id raysubmit_abc123 --action logs

  # Verify Ray cluster resources
  %(prog)s --head-pod training-head-xxxxx --action resources
        """
    )
    
    parser.add_argument('--head-pod', required=True, help='Name of the Ray head pod')
    parser.add_argument('--job-name', help='Name of the training job (for auto-restart)')
    parser.add_argument('--job-id', help='Ray job ID (for monitoring existing jobs)')
    parser.add_argument('--checkpoint-dir', help='Directory containing checkpoints')
    parser.add_argument('--action', default='monitor',
                       choices=['monitor', 'status', 'step', 'stall', 'gpu', 'resources', 'logs', 'health', 'efa'],
                       help='Action to perform (default: monitor)')
    parser.add_argument('--max-retries', type=int, default=10, help='Maximum restart attempts')
    parser.add_argument('--retry-delay', type=int, default=60, help='Seconds between retries')
    parser.add_argument('--stagnation-threshold', type=int, default=300, 
                       help='Seconds without progress to consider stalled')
    parser.add_argument('--check-interval', type=int, default=30, 
                       help='Seconds between status checks')
    parser.add_argument('--namespace', default='default', help='Kubernetes namespace')
    parser.add_argument('--json', action='store_true', help='Output results as JSON')
    
    args = parser.parse_args()
    
    # Route to appropriate action
    if args.action == 'monitor':
        if not args.job_name:
            print("Error: --job-name required for auto-restart monitoring")
            sys.exit(1)
        if not args.checkpoint_dir:
            print("Error: --checkpoint-dir required for auto-restart monitoring")
            sys.exit(1)
        
        print(f"Starting auto-restart monitoring for job '{args.job_name}'")
        print(f"Head pod: {args.head_pod}")
        print(f"Checkpoint dir: {args.checkpoint_dir}")
        print(f"Max retries: {args.max_retries}")
        print("Press Ctrl+C to stop monitoring\n")
        
        result = run_skill_function(
            'auto_restart',
            head_pod=args.head_pod,
            job_name=args.job_name,
            checkpoint_dir=args.checkpoint_dir,
            max_retries=args.max_retries,
            retry_delay=args.retry_delay,
            stagnation_threshold=args.stagnation_threshold,
            check_interval=args.check_interval
        )
        
    elif args.action == 'status':
        if not args.job_id:
            print("Error: --job-id required for status check")
            sys.exit(1)
        
        result = run_skill_function(
            'check_job_status',
            head_pod=args.head_pod,
            job_id=args.job_id
        )
        
        if not args.json:
            print(f"Job Status: {result}")
            
    elif args.action == 'step':
        if not args.job_id:
            print("Error: --job-id required for step check")
            sys.exit(1)
        
        result = run_skill_function(
            'get_current_step',
            head_pod=args.head_pod,
            job_id=args.job_id
        )
        
        if not args.json:
            if result:
                print(f"Current Step: {result}")
            else:
                print("Current Step: Not found in logs")
                
    elif args.action == 'stall':
        if not args.job_id:
            print("Error: --job-id required for stall detection")
            sys.exit(1)
        
        result = run_skill_function(
            'detect_stall',
            head_pod=args.head_pod,
            job_id=args.job_id,
            stagnation_threshold=args.stagnation_threshold
        )
        
        if not args.json:
            status = "STALLED" if result else "Making progress"
            print(f"Stall Status: {status}")
            
    elif args.action == 'gpu':
        result = run_skill_function(
            'check_gpu_utilization',
            head_pod=args.head_pod,
            namespace=args.namespace
        )
        
        if not args.json:
            if isinstance(result, dict) and result.get('healthy'):
                print(f"GPU Count: {result['gpu_count']}")
                print(f"Average Utilization: {result['avg_utilization']:.1f}%")
                for i, util in enumerate(result['gpu_utilizations']):
                    mem_used = result['memory_used'][i]
                    mem_total = result['memory_total'][i]
                    print(f"  GPU {i}: {util}% (Memory: {mem_used}/{mem_total} MB)")
            else:
                print(f"GPU Check Failed: {result}")
                
    elif args.action == 'resources':
        result = run_skill_function(
            'verify_ray_resources',
            head_pod=args.head_pod,
            namespace=args.namespace
        )
        
        if not args.json:
            if isinstance(result, dict) and result.get('healthy'):
                print(f"GPUs: {result['gpus_used']}/{result['gpus_available']} used")
                print(f"CPUs: {result['cpus_used']}/{result['cpus_available']} used")
                if result['gpus_available'] > 0 and result['gpus_used'] == 0:
                    print("WARNING: GPUs available but not being used!")
            else:
                print(f"Resource Check Failed: {result}")
                
    elif args.action == 'logs':
        if not args.job_id:
            print("Error: --job-id required for log watching")
            sys.exit(1)
        
        result = watch_logs(args.head_pod, args.job_id, follow=True)
    
    elif args.action == 'health':
        if not args.checkpoint_dir:
            print("Error: --checkpoint-dir required for health check")
            sys.exit(1)
        
        result = run_skill_function(
            'get_training_health',
            head_pod=args.head_pod,
            checkpoint_dir=args.checkpoint_dir,
            namespace=args.namespace
        )
        
        if not args.json:
            if isinstance(result, dict) and 'healthy' in result:
                run_skill_function('print_training_health', result)
            else:
                print(f"Health Check Failed: {result}")
    
    elif args.action == 'efa':
        result = run_skill_function(
            'check_efa_utilization',
            head_pod=args.head_pod,
            namespace=args.namespace
        )
        
        if not args.json:
            if isinstance(result, dict):
                active = "ACTIVE (EFA)" if result.get('efa_active') else "INACTIVE"
                print(f"EFA Status: {active}")
                print(f"Transport: {result.get('transport', 'unknown')}")
                if result.get('details'):
                    print(f"Details: {result['details']}")
            else:
                print(f"EFA Check Failed: {result}")
    
    # Output JSON if requested
    if args.json:
        print(json.dumps(result, indent=2, default=str))
    
    # Return appropriate exit code
    if isinstance(result, dict):
        if 'error' in result:
            sys.exit(1)
        if result.get('success') is False:
            sys.exit(1)
    
    sys.exit(0)


if __name__ == '__main__':
    main()
