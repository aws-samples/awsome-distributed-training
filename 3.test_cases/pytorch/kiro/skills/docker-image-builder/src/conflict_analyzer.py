#!/usr/bin/env python3
"""
Conflict Analyzer for Docker builds.
Detects and suggests fixes for common compatibility issues.
"""

import re
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from enum import Enum


class ConflictSeverity(Enum):
    """Severity levels for conflicts."""
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


@dataclass
class Conflict:
    """Represents a detected conflict."""
    type: str
    severity: ConflictSeverity
    message: str
    file: str
    line: Optional[int] = None
    current_value: Optional[str] = None
    suggested_value: Optional[str] = None
    fix_action: Optional[str] = None


class ConflictAnalyzer:
    """Analyzes Docker builds for conflicts."""
    
    # Known incompatible combinations
    PYTORCH_CUDA_COMPATIBILITY = {
        '2.7': ['12.8'],
        '2.6': ['12.4', '12.8'],
        '2.5': ['12.4', '12.1'],
        '2.4': ['12.1', '11.8'],
        '2.3': ['12.1', '11.8'],
        '2.2': ['12.1', '11.8'],
        '2.1': ['12.1', '11.8'],
        '2.0': ['11.8', '11.7'],
    }
    
    TORCH_TORCHVISION_COMPATIBILITY = {
        '2.7': ['0.22'],
        '2.6': ['0.21'],
        '2.5': ['0.20'],
        '2.4': ['0.19'],
        '2.3': ['0.18'],
        '2.2': ['0.17'],
        '2.1': ['0.16'],
        '2.0': ['0.15'],
    }
    
    def __init__(self):
        self.conflicts = []
    
    def analyze(self, dockerfile_content: str, requirements_content: str) -> List[Conflict]:
        """Analyze both Dockerfile and requirements for conflicts."""
        self.conflicts = []
        
        # Analyze Dockerfile
        self._analyze_dockerfile(dockerfile_content)
        
        # Analyze requirements
        self._analyze_requirements(requirements_content)
        
        # Cross-reference analysis
        self._cross_reference_analysis()
        
        return self.conflicts
    
    def _analyze_dockerfile(self, content: str):
        """Analyze Dockerfile content."""
        lines = content.split('\n')
        
        for line_num, line in enumerate(lines, 1):
            line = line.strip()
            
            # Check FROM statements
            if line.upper().startswith('FROM '):
                self._check_base_image(line, line_num)
            
            # Check RUN statements for pip installs
            elif line.upper().startswith('RUN '):
                self._check_run_command(line, line_num)
    
    def _check_base_image(self, line: str, line_num: int):
        """Check base image compatibility."""
        # Extract image name
        match = re.search(r'FROM\s+(\S+)', line, re.IGNORECASE)
        if not match:
            return
        
        image = match.group(1)
        
        # Check if it's a PyTorch image
        if 'pytorch' in image.lower():
            # Extract CUDA version
            cuda_match = re.search(r'cuda(\d+\.\d+)', image.lower())
            pytorch_match = re.search(r'pytorch:(\d+\.\d+)', image.lower())
            
            if pytorch_match and cuda_match:
                pytorch_ver = pytorch_match.group(1)
                cuda_ver = cuda_match.group(1)
                
                # Check compatibility
                compatible_cudas = self.PYTORCH_CUDA_COMPATIBILITY.get(pytorch_ver, [])
                
                if cuda_ver not in compatible_cudas:
                    suggested_cuda = compatible_cudas[0] if compatible_cudas else '12.4'
                    suggested_image = f"pytorch/pytorch:{pytorch_ver}-cuda{suggested_cuda}-cudnn9-runtime"
                    
                    self.conflicts.append(Conflict(
                        type='pytorch_cuda_mismatch',
                        severity=ConflictSeverity.ERROR,
                        message=f'PyTorch {pytorch_ver} is not compatible with CUDA {cuda_ver}',
                        file='Dockerfile',
                        line=line_num,
                        current_value=image,
                        suggested_value=suggested_image,
                        fix_action='replace_from'
                    ))
    
    def _check_run_command(self, line: str, line_num: int):
        """Check RUN commands for issues."""
        # Check for pip install with --no-cache-dir missing
        if 'pip install' in line.lower() and '--no-cache-dir' not in line.lower():
            self.conflicts.append(Conflict(
                type='missing_no_cache',
                severity=ConflictSeverity.WARNING,
                message='pip install without --no-cache-dir increases image size',
                file='Dockerfile',
                line=line_num,
                fix_action='add_no_cache'
            ))
    
    def _analyze_requirements(self, content: str):
        """Analyze requirements.txt content."""
        packages = {}
        
        for line_num, line in enumerate(content.split('\n'), 1):
            line = line.strip()
            if not line or line.startswith('#') or line.startswith('--'):
                continue
            
            # Parse package==version
            match = re.match(r'^([a-zA-Z0-9_-]+)(?:==([\d.]+))?', line)
            if match:
                pkg_name = match.group(1).lower()
                version = match.group(2)
                packages[pkg_name] = {'version': version, 'line': line_num}
        
        # Check torch/torchvision compatibility
        torch_info = packages.get('torch')
        torchvision_info = packages.get('torchvision')
        
        if torch_info and torchvision_info:
            torch_ver = torch_info['version']
            torchvision_ver = torchvision_info['version']
            
            if torch_ver and torchvision_ver:
                # Get major.minor
                torch_minor = '.'.join(torch_ver.split('.')[:2])
                compatible_torchvisions = self.TORCH_TORCHVISION_COMPATIBILITY.get(torch_minor, [])
                
                # Check if torchvision version is compatible
                if not any(torchvision_ver.startswith(v) for v in compatible_torchvisions):
                    suggested = compatible_torchvisions[0] if compatible_torchvisions else None
                    
                    self.conflicts.append(Conflict(
                        type='torch_torchvision_mismatch',
                        severity=ConflictSeverity.ERROR,
                        message=f'torch=={torch_ver} is incompatible with torchvision=={torchvision_ver}',
                        file='requirements.txt',
                        line=torchvision_info['line'],
                        current_value=f'torchvision=={torchvision_ver}',
                        suggested_value=f'torchvision=={suggested}' if suggested else None,
                        fix_action='update_torchvision' if suggested else 'remove_torchvision'
                    ))
        
        # Check for torchaudio compatibility
        torchaudio_info = packages.get('torchaudio')
        if torch_info and torchaudio_info:
            torch_ver = torch_info['version']
            torchaudio_ver = torchaudio_info['version']
            
            if torch_ver and torchaudio_ver:
                # Simple check - versions should match major.minor
                torch_minor = '.'.join(torch_ver.split('.')[:2])
                torchaudio_minor = '.'.join(torchaudio_ver.split('.')[:2])
                
                if torch_minor != torchaudio_minor:
                    self.conflicts.append(Conflict(
                        type='torch_torchaudio_mismatch',
                        severity=ConflictSeverity.WARNING,
                        message=f'torch=={torch_ver} may be incompatible with torchaudio=={torchaudio_ver}',
                        file='requirements.txt',
                        line=torchaudio_info['line'],
                        current_value=f'torchaudio=={torchaudio_ver}',
                        suggested_value=f'torchaudio=={torch_minor}.0',
                        fix_action='update_torchaudio'
                    ))
    
    def _cross_reference_analysis(self):
        """Cross-reference Dockerfile and requirements analysis."""
        # This could check if versions in requirements match base image
        pass
    
    def get_fixable_conflicts(self) -> List[Conflict]:
        """Get conflicts that can be automatically fixed."""
        return [c for c in self.conflicts if c.fix_action is not None]
    
    def get_critical_conflicts(self) -> List[Conflict]:
        """Get critical conflicts that must be resolved."""
        return [c for c in self.conflicts if c.severity in [ConflictSeverity.ERROR, ConflictSeverity.CRITICAL]]
    
    def generate_report(self) -> str:
        """Generate human-readable conflict report."""
        if not self.conflicts:
            return "✅ No conflicts detected"
        
        lines = ["Conflict Report", "=" * 50]
        
        for conflict in self.conflicts:
            icon = {
                ConflictSeverity.INFO: "ℹ️",
                ConflictSeverity.WARNING: "⚠️",
                ConflictSeverity.ERROR: "❌",
                ConflictSeverity.CRITICAL: "🚨"
            }.get(conflict.severity, "•")
            
            lines.append(f"\n{icon} [{conflict.severity.value.upper()}] {conflict.type}")
            lines.append(f"   File: {conflict.file}" + (f":{conflict.line}" if conflict.line else ""))
            lines.append(f"   Message: {conflict.message}")
            
            if conflict.current_value:
                lines.append(f"   Current: {conflict.current_value}")
            
            if conflict.suggested_value:
                lines.append(f"   Suggested: {conflict.suggested_value}")
            
            if conflict.fix_action:
                lines.append(f"   Fix: {conflict.fix_action}")
        
        return '\n'.join(lines)


def main():
    """CLI for testing conflict analyzer."""
    import sys
    
    if len(sys.argv) < 3:
        print("Usage: conflict_analyzer.py <dockerfile> <requirements.txt>")
        sys.exit(1)
    
    dockerfile_path = sys.argv[1]
    requirements_path = sys.argv[2]
    
    with open(dockerfile_path, 'r') as f:
        dockerfile_content = f.read()
    
    with open(requirements_path, 'r') as f:
        requirements_content = f.read()
    
    analyzer = ConflictAnalyzer()
    conflicts = analyzer.analyze(dockerfile_content, requirements_content)
    
    print(analyzer.generate_report())
    
    # Exit with error if critical conflicts exist
    if analyzer.get_critical_conflicts():
        sys.exit(1)


if __name__ == '__main__':
    main()
