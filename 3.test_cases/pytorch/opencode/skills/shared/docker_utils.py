"""
Shared Docker utilities for opencode skills.
"""

import subprocess
import json
import re
from typing import Optional, List, Dict, Tuple
from pathlib import Path


class DockerClient:
    """Docker client wrapper."""
    
    def __init__(self, use_sudo: bool = False):
        self.use_sudo = use_sudo
        self.base_cmd = ['sudo'] if use_sudo else []
    
    def _run(self, cmd: List[str], **kwargs) -> subprocess.CompletedProcess:
        """Run docker command."""
        full_cmd = self.base_cmd + ['docker'] + cmd
        return subprocess.run(full_cmd, capture_output=True, text=True, **kwargs)
    
    def build(self, context: str, tag: str, dockerfile: Optional[str] = None,
              build_args: Optional[Dict[str, str]] = None, no_cache: bool = False) -> Tuple[bool, str]:
        """Build Docker image."""
        cmd = ['build', '-t', tag]
        
        if dockerfile:
            cmd.extend(['-f', dockerfile])
        
        if no_cache:
            cmd.append('--no-cache')
        
        if build_args:
            for key, value in build_args.items():
                cmd.extend(['--build-arg', f'{key}={value}'])
        
        cmd.append(context)
        
        result = self._run(cmd)
        return result.returncode == 0, result.stderr + result.stdout
    
    def tag(self, source: str, target: str) -> bool:
        """Tag Docker image."""
        result = self._run(['tag', source, target])
        return result.returncode == 0
    
    def push(self, image: str) -> Tuple[bool, str]:
        """Push Docker image."""
        result = self._run(['push', image])
        return result.returncode == 0, result.stderr + result.stdout
    
    def pull(self, image: str) -> Tuple[bool, str]:
        """Pull Docker image."""
        result = self._run(['pull', image])
        return result.returncode == 0, result.stderr + result.stdout
    
    def run(self, image: str, command: Optional[List[str]] = None,
            volumes: Optional[List[Tuple[str, str]]] = None,
            environment: Optional[Dict[str, str]] = None,
            gpus: Optional[str] = None,
            remove: bool = True) -> Tuple[bool, str]:
        """Run Docker container."""
        cmd = ['run']
        
        if remove:
            cmd.append('--rm')
        
        if gpus:
            cmd.extend(['--gpus', gpus])
        
        if volumes:
            for host, container in volumes:
                cmd.extend(['-v', f'{host}:{container}'])
        
        if environment:
            for key, value in environment.items():
                cmd.extend(['-e', f'{key}={value}'])
        
        cmd.append(image)
        
        if command:
            cmd.extend(command)
        
        result = self._run(cmd)
        return result.returncode == 0, result.stderr + result.stdout
    
    def images(self, filter_name: Optional[str] = None) -> List[Dict]:
        """List Docker images."""
        cmd = ['images', '--format', '{{json .}}']
        
        if filter_name:
            cmd.extend(['--filter', f'reference={filter_name}'])
        
        result = self._run(cmd)
        
        if result.returncode != 0:
            return []
        
        images = []
        for line in result.stdout.strip().split('\n'):
            if line:
                try:
                    images.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
        
        return images
    
    def inspect(self, image: str) -> Optional[Dict]:
        """Inspect Docker image."""
        result = self._run(['inspect', '--type', 'image', image])
        
        if result.returncode != 0:
            return None
        
        try:
            return json.loads(result.stdout)[0]
        except (json.JSONDecodeError, IndexError):
            return None
    
    def rmi(self, image: str, force: bool = False) -> bool:
        """Remove Docker image."""
        cmd = ['rmi']
        if force:
            cmd.append('-f')
        cmd.append(image)
        
        result = self._run(cmd)
        return result.returncode == 0


def check_docker_installed() -> bool:
    """Check if Docker is installed."""
    try:
        result = subprocess.run(['docker', '--version'], capture_output=True)
        return result.returncode == 0
    except FileNotFoundError:
        return False


def check_docker_running() -> bool:
    """Check if Docker daemon is running."""
    try:
        result = subprocess.run(['docker', 'info'], capture_output=True)
        return result.returncode == 0
    except Exception:
        return False


def parse_dockerfile(dockerfile_path: str) -> Dict:
    """Parse Dockerfile and extract key information."""
    path = Path(dockerfile_path)
    
    if not path.exists():
        return {}
    
    content = path.read_text()
    
    info = {
        'from': [],
        'run': [],
        'copy': [],
        'env': {},
        'workdir': None,
        'expose': [],
        'cmd': None,
        'entrypoint': None
    }
    
    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        
        # Extract FROM
        if line.upper().startswith('FROM '):
            info['from'].append(line[5:].strip())
        
        # Extract RUN
        elif line.upper().startswith('RUN '):
            info['run'].append(line[4:].strip())
        
        # Extract COPY
        elif line.upper().startswith('COPY '):
            info['copy'].append(line[5:].strip())
        
        # Extract ENV
        elif line.upper().startswith('ENV '):
            env_line = line[4:].strip()
            if '=' in env_line:
                key, value = env_line.split('=', 1)
                info['env'][key] = value
        
        # Extract WORKDIR
        elif line.upper().startswith('WORKDIR '):
            info['workdir'] = line[8:].strip()
        
        # Extract EXPOSE
        elif line.upper().startswith('EXPOSE '):
            info['expose'].append(line[7:].strip())
    
    return info


def analyze_base_image_compatibility(base_image: str) -> Dict:
    """Analyze base image for PyTorch/CUDA compatibility."""
    compatibility = {
        'image': base_image,
        'cuda_version': None,
        'pytorch_version': None,
        'python_version': None,
        'issues': []
    }
    
    # Extract CUDA version from image tag
    cuda_match = re.search(r'cuda(\d+\.\d+)', base_image.lower())
    if cuda_match:
        compatibility['cuda_version'] = cuda_match.group(1)
    
    # Extract PyTorch version
    pytorch_match = re.search(r'pytorch:(\d+\.\d+\.?\d*)', base_image.lower())
    if pytorch_match:
        compatibility['pytorch_version'] = pytorch_match.group(1)
    
    # Check for known compatibility issues
    if compatibility['cuda_version'] and compatibility['pytorch_version']:
        # PyTorch 2.5+ requires CUDA 12.1+
        if float(compatibility['pytorch_version'][:3]) >= 2.5:
            if float(compatibility['cuda_version']) < 12.1:
                compatibility['issues'].append(
                    f"PyTorch {compatibility['pytorch_version']} requires CUDA 12.1+, "
                    f"but base image has CUDA {compatibility['cuda_version']}"
                )
    
    return compatibility


def get_recommended_base_image(cuda_version: Optional[str] = None,
                               pytorch_version: Optional[str] = None) -> str:
    """Get recommended PyTorch base image based on requirements."""
    
    # Default to stable combination
    if not cuda_version and not pytorch_version:
        return "pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime"
    
    # Map PyTorch versions to compatible CUDA versions
    pytorch_cuda_map = {
        '2.7': '12.8',
        '2.6': '12.4',
        '2.5': '12.4',
        '2.4': '12.1',
        '2.3': '12.1',
        '2.2': '12.1',
        '2.1': '12.1',
        '2.0': '11.8'
    }
    
    if pytorch_version:
        major_minor = '.'.join(pytorch_version.split('.')[:2])
        recommended_cuda = pytorch_cuda_map.get(major_minor, '12.4')
        
        return f"pytorch/pytorch:{pytorch_version}-cuda{recommended_cuda}-cudnn9-runtime"
    
    if cuda_version:
        # Find compatible PyTorch version
        for pt_ver, cu_ver in pytorch_cuda_map.items():
            if cu_ver == cuda_version:
                return f"pytorch/pytorch:{pt_ver}.1-cuda{cuda_version}-cudnn9-runtime"
    
    return "pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime"


def check_image_exists_locally(image_name: str, use_sudo: bool = False) -> bool:
    """Check if image exists locally."""
    client = DockerClient(use_sudo=use_sudo)
    images = client.images(filter_name=image_name)
    return len(images) > 0
