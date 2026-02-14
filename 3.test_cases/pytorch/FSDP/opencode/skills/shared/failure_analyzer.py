"""
Failure Analyzer - Detect job failures and suggest/auto-apply fixes.
"""

import re
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from enum import Enum


class FailureSeverity(Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


@dataclass
class FailurePattern:
    name: str
    patterns: List[str]
    severity: FailureSeverity
    auto_fixable: bool
    fix_action: str
    fix_description: str


class FailureAnalyzer:
    """Analyze training job failures and provide fixes."""
    
    FAILURE_PATTERNS = [
        FailurePattern(
            name="OOM_ERROR",
            patterns=[
                r'OutOfMemoryError',
                r'exit code 137',
                r'CUDA out of memory',
                r'RuntimeError: CUDA error: out of memory'
            ],
            severity=FailureSeverity.HIGH,
            auto_fixable=True,
            fix_action="reduce_batch_size",
            fix_description="Reduce batch size by 50%"
        ),
        FailurePattern(
            name="IMAGE_PULL_ERROR",
            patterns=[
                r'ImagePullBackOff',
                r'ErrImagePull',
                r'not found',
                r'Failed to pull image'
            ],
            severity=FailureSeverity.CRITICAL,
            auto_fixable=True,
            fix_action="update_image_uri",
            fix_description="Update to latest available image tag"
        ),
        FailurePattern(
            name="NCCL_TIMEOUT",
            patterns=[
                r'NCCL operation timeout',
                r'connection closed by peer',
                r'NCCL error: unhandled system error'
            ],
            severity=FailureSeverity.HIGH,
            auto_fixable=True,
            fix_action="increase_timeout",
            fix_description="Increase NCCL timeout and check network"
        ),
        FailurePattern(
            name="NCCL_ERROR",
            patterns=[
                r'NCCL error',
                r'ncclSystemError',
                r'ncclInternalError'
            ],
            severity=FailureSeverity.HIGH,
            auto_fixable=False,
            fix_action="none",
            fix_description="Check EFA configuration and network connectivity"
        ),
        FailurePattern(
            name="GPU_NOT_AVAILABLE",
            patterns=[
                r'no GPU available',
                r'Failed to allocate',
                r'CUDA error: no CUDA-capable device',
                r'RuntimeError: No CUDA GPUs are available'
            ],
            severity=FailureSeverity.CRITICAL,
            auto_fixable=False,
            fix_action="none",
            fix_description="Check GPU device plugin and node status"
        ),
        FailurePattern(
            name="STORAGE_FULL",
            patterns=[
                r'no space left on device',
                r'DiskPressure',
                r'Write failed',
                r'IOError.*No space left'
            ],
            severity=FailureSeverity.HIGH,
            auto_fixable=True,
            fix_action="cleanup_storage",
            fix_description="Clean up old checkpoints and logs"
        ),
        FailurePattern(
            name="PYTHON_ERROR",
            patterns=[
                r'Traceback \(most recent call last\)',
                r'SyntaxError',
                r'ImportError',
                r'ModuleNotFoundError'
            ],
            severity=FailureSeverity.HIGH,
            auto_fixable=False,
            fix_action="none",
            fix_description="Check code and dependencies"
        ),
        FailurePattern(
            name="CHECKPOINT_ERROR",
            patterns=[
                r'Checkpoint save failed',
                r'Permission denied.*checkpoint',
                r'No such file or directory.*checkpoint'
            ],
            severity=FailureSeverity.MEDIUM,
            auto_fixable=True,
            fix_action="fix_checkpoint_path",
            fix_description="Ensure checkpoint directory exists and is writable"
        ),
        FailurePattern(
            name="DATASET_ERROR",
            patterns=[
                r'Dataset not found',
                r'Failed to load dataset',
                r'HuggingFace Hub error',
                r'Connection error.*huggingface'
            ],
            severity=FailureSeverity.MEDIUM,
            auto_fixable=False,
            fix_action="none",
            fix_description="Check dataset name and HuggingFace token"
        )
    ]
    
    def __init__(self):
        self.detected_failures = []
    
    def analyze_logs(self, logs: str) -> List[Dict]:
        """Analyze logs for failure patterns."""
        failures = []
        
        for pattern in self.FAILURE_PATTERNS:
            for regex_pattern in pattern.patterns:
                if re.search(regex_pattern, logs, re.IGNORECASE):
                    failures.append({
                        'name': pattern.name,
                        'severity': pattern.severity.value,
                        'auto_fixable': pattern.auto_fixable,
                        'fix_action': pattern.fix_action,
                        'fix_description': pattern.fix_description,
                        'matched_pattern': regex_pattern
                    })
                    break  # Only match once per pattern type
        
        self.detected_failures = failures
        return failures
    
    def detect_failure_type(self, pod_status: str, logs: str) -> Optional[Dict]:
        """Determine failure type from status and logs."""
        # First check logs
        log_failures = self.analyze_logs(logs)
        if log_failures:
            # Return the most severe failure
            severity_order = ['critical', 'high', 'medium', 'low']
            log_failures.sort(key=lambda x: severity_order.index(x['severity']))
            return log_failures[0]
        
        # Check pod status
        if 'OOMKilled' in pod_status or 'exit code 137' in pod_status:
            return {
                'name': 'OOM_ERROR',
                'severity': 'high',
                'auto_fixable': True,
                'fix_action': 'reduce_batch_size',
                'fix_description': 'Reduce batch size by 50%'
            }
        
        if 'Error' in pod_status or 'CrashLoopBackOff' in pod_status:
            return {
                'name': 'UNKNOWN_ERROR',
                'severity': 'high',
                'auto_fixable': False,
                'fix_action': 'none',
                'fix_description': 'Unknown error - check logs for details'
            }
        
        return None
    
    def suggest_fix(self, failure: Dict, job_config: Dict) -> Dict:
        """Generate specific fix recommendation."""
        fix = {
            'action': failure.get('fix_action', 'none'),
            'description': failure.get('fix_description', 'No fix available'),
            'config_changes': {},
            'safe_to_auto_apply': failure.get('auto_fixable', False)
        }
        
        action = failure.get('fix_action')
        
        if action == 'reduce_batch_size':
            current_batch = job_config.get('train_batch_size', 4)
            new_batch = max(1, current_batch // 2)
            fix['config_changes'] = {'train_batch_size': new_batch}
            fix['description'] = f"Reduce batch size from {current_batch} to {new_batch}"
        
        elif action == 'update_image_uri':
            current_image = job_config.get('image_uri', '')
            # Suggest using 'latest' tag
            if ':' in current_image:
                new_image = current_image.rsplit(':', 1)[0] + ':latest'
            else:
                new_image = current_image + ':latest'
            fix['config_changes'] = {'image_uri': new_image}
            fix['description'] = f"Update image from {current_image} to {new_image}"
        
        elif action == 'increase_timeout':
            fix['config_changes'] = {
                'env_vars': {
                    'NCCL_TIMEOUT': '3600',
                    'NCCL_DEBUG': 'INFO'
                }
            }
            fix['description'] = "Increase NCCL timeout to 3600 seconds and enable debug logging"
        
        elif action == 'cleanup_storage':
            fix['description'] = "Clean up old checkpoints in /checkpoints directory"
            fix['manual_steps'] = [
                "kubectl exec -it <pod-name> -- rm -rf /checkpoints/old-checkpoints",
                "Or increase storage volume size"
            ]
        
        elif action == 'fix_checkpoint_path':
            fix['config_changes'] = {'checkpoint_dir': '/tmp/checkpoints'}
            fix['description'] = "Use /tmp/checkpoints as checkpoint directory"
        
        return fix
    
    def apply_fix(self, fix: Dict, job_config: Dict) -> Dict:
        """Apply fix to job configuration."""
        new_config = job_config.copy()
        
        # Apply config changes
        for key, value in fix.get('config_changes', {}).items():
            if isinstance(value, dict) and key in new_config and isinstance(new_config[key], dict):
                # Merge nested dicts (like env_vars)
                new_config[key].update(value)
            else:
                new_config[key] = value
        
        return new_config
    
    def should_auto_retry(self, failure: Dict) -> bool:
        """Determine if auto-retry is safe for this failure."""
        if not failure.get('auto_fixable', False):
            return False
        
        # Don't auto-retry critical failures without confirmation
        if failure.get('severity') == 'critical':
            return False
        
        # Safe to auto-retry
        return True
    
    def generate_failure_report(self, failures: List[Dict], job_config: Dict) -> str:
        """Generate human-readable failure report."""
        if not failures:
            return "✅ No failures detected"
        
        lines = ["\n" + "="*80, "FAILURE ANALYSIS REPORT", "="*80]
        
        for i, failure in enumerate(failures, 1):
            severity_icon = {
                'critical': '🚨',
                'high': '❌',
                'medium': '⚠️',
                'low': 'ℹ️'
            }.get(failure.get('severity', 'low'), '•')
            
            lines.append(f"\n{severity_icon} [{i}] {failure.get('name', 'Unknown')}")
            lines.append(f"    Severity: {failure.get('severity', 'unknown').upper()}")
            lines.append(f"    Auto-fixable: {'Yes' if failure.get('auto_fixable') else 'No'}")
            lines.append(f"    Suggested fix: {failure.get('fix_description', 'None')}")
            
            if failure.get('auto_fixable'):
                fix = self.suggest_fix(failure, job_config)
                if fix.get('config_changes'):
                    lines.append(f"    Config changes: {fix['config_changes']}")
        
        lines.append("\n" + "="*80)
        return "\n".join(lines)
    
    def get_retry_recommendation(self, failure: Dict, attempt: int, max_attempts: int) -> Tuple[bool, str]:
        """Get recommendation on whether to retry."""
        if attempt >= max_attempts:
            return False, f"Max retry attempts ({max_attempts}) reached"
        
        if not failure.get('auto_fixable', False):
            return False, "Failure is not auto-fixable. Manual intervention required."
        
        if failure.get('severity') == 'critical':
            return False, "Critical failure requires manual review before retry"
        
        return True, f"Safe to retry (attempt {attempt + 1}/{max_attempts})"
