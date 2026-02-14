#!/usr/bin/env python3
"""
Docker Image Builder Skill
Intelligently builds Docker images with automatic conflict detection and resolution.
"""

import argparse
import sys
import os
import subprocess
import tempfile
import shutil
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Tuple

# Add shared utilities to path
sys.path.insert(0, os.path.expanduser('~/.opencode/skills/shared'))

from logger import create_logger, StatusReporter
from docker_utils import (
    DockerClient, parse_dockerfile, analyze_base_image_compatibility,
    get_recommended_base_image, check_docker_installed, check_docker_running
)


class ConflictAnalyzer:
    """Analyzes Dockerfile and requirements for conflicts."""
    
    def __init__(self, logger):
        self.logger = logger
        self.conflicts = []
        self.fixes = []
    
    def analyze_dockerfile(self, dockerfile_path: str) -> Dict:
        """Analyze Dockerfile for issues."""
        self.logger.info(f"Analyzing Dockerfile: {dockerfile_path}")
        
        dockerfile_info = parse_dockerfile(dockerfile_path)
        issues = []
        
        # Check base image
        if dockerfile_info.get('from'):
            base_image = dockerfile_info['from'][0]
            compatibility = analyze_base_image_compatibility(base_image)
            
            if compatibility['issues']:
                for issue in compatibility['issues']:
                    issues.append({
                        'type': 'base_image_compatibility',
                        'severity': 'error',
                        'message': issue,
                        'current': base_image,
                        'suggested': get_recommended_base_image()
                    })
        
        return {
            'info': dockerfile_info,
            'issues': issues
        }
    
    def analyze_requirements(self, requirements_path: str) -> Dict:
        """Analyze requirements.txt for conflicts."""
        self.logger.info(f"Analyzing requirements: {requirements_path}")
        
        if not os.path.exists(requirements_path):
            return {'packages': [], 'issues': []}
        
        packages = {}
        issues = []
        
        with open(requirements_path, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or line.startswith('--'):
                    continue
                
                # Parse package==version
                if '==' in line:
                    pkg, ver = line.split('==', 1)
                    packages[pkg.lower()] = ver
        
        # Check for known conflicts
        torch_ver = packages.get('torch', '')
        torchvision_ver = packages.get('torchvision', '')
        
        if torch_ver and torchvision_ver:
            # PyTorch 2.5+ compatibility
            if torch_ver.startswith('2.7') or torch_ver.startswith('2.6'):
                if not torchvision_ver.startswith(('0.22', '0.21')):
                    issues.append({
                        'type': 'version_conflict',
                        'severity': 'warning',
                        'message': f'torch=={torch_ver} may conflict with torchvision=={torchvision_ver}',
                        'suggested_action': 'Remove torchvision or update to compatible version'
                    })
        
        return {
            'packages': packages,
            'issues': issues
        }
    
    def get_fixes(self, dockerfile_issues: List[Dict], requirements_issues: List[Dict]) -> List[Dict]:
        """Generate list of fixes to apply."""
        fixes = []
        
        # Dockerfile fixes
        for issue in dockerfile_issues:
            if issue['type'] == 'base_image_compatibility':
                fixes.append({
                    'file': 'Dockerfile',
                    'action': 'replace_base_image',
                    'old': issue['current'],
                    'new': issue['suggested'],
                    'reason': issue['message']
                })
        
        # Requirements fixes
        for issue in requirements_issues:
            if issue['type'] == 'version_conflict':
                if 'torchvision' in issue['message']:
                    fixes.append({
                        'file': 'requirements.txt',
                        'action': 'remove_package',
                        'package': 'torchvision',
                        'reason': issue['message']
                    })
        
        return fixes


class DockerfilePatcher:
    """Patches Dockerfile with fixes."""
    
    def __init__(self, logger):
        self.logger = logger
    
    def apply_fixes(self, dockerfile_path: str, fixes: List[Dict]) -> str:
        """Apply fixes to Dockerfile and return new content."""
        with open(dockerfile_path, 'r') as f:
            content = f.read()
        
        for fix in fixes:
            if fix['file'] != 'Dockerfile':
                continue
            
            if fix['action'] == 'replace_base_image':
                self.logger.info(f"🔧 Fixing: Replacing base image {fix['old']} → {fix['new']}")
                content = content.replace(f"FROM {fix['old']}", f"FROM {fix['new']}")
        
        return content
    
    def patch_requirements(self, requirements_path: str, fixes: List[Dict]) -> str:
        """Apply fixes to requirements.txt and return new content."""
        if not os.path.exists(requirements_path):
            return ""
        
        with open(requirements_path, 'r') as f:
            lines = f.readlines()
        
        new_lines = []
        for line in lines:
            keep_line = True
            
            for fix in fixes:
                if fix['file'] != 'requirements.txt':
                    continue
                
                if fix['action'] == 'remove_package':
                    pkg_name = fix['package'].lower()
                    if line.lower().startswith(pkg_name):
                        self.logger.info(f"🔧 Fixing: Removing {fix['package']} ({fix['reason']})")
                        keep_line = False
            
            if keep_line:
                new_lines.append(line)
        
        return ''.join(new_lines)


class SmokeTester:
    """Runs quick smoke tests on built images."""
    
    def __init__(self, logger, docker_client: DockerClient):
        self.logger = logger
        self.docker = docker_client
    
    def test_imports(self, image_name: str) -> Tuple[bool, str]:
        """Test basic imports in container."""
        self.logger.info("Running smoke test: import validation")
        
        test_script = """
import sys
print(f"Python: {sys.version}")

try:
    import torch
    print(f"✓ PyTorch: {torch.__version__}")
except ImportError as e:
    print(f"✗ PyTorch import failed: {e}")
    sys.exit(1)

try:
    import transformers
    print(f"✓ Transformers: {transformers.__version__}")
except ImportError as e:
    print(f"✗ Transformers import failed: {e}")
    sys.exit(1)

try:
    import datasets
    print(f"✓ Datasets: {datasets.__version__}")
except ImportError as e:
    print(f"✗ Datasets import failed: {e}")
    sys.exit(1)

print("All imports successful!")
"""
        
        success, output = self.docker.run(
            image_name,
            command=['python', '-c', test_script]
        )
        
        return success, output


class ImageBuilder:
    """Main image builder with auto-fix capabilities."""
    
    def __init__(self, args):
        self.args = args
        self.logger = create_logger('docker-image-builder', verbose=args.verbose)
        self.reporter = StatusReporter(self.logger)
        self.docker = DockerClient(use_sudo=args.use_sudo)
        self.analyzer = ConflictAnalyzer(self.logger)
        self.patcher = DockerfilePatcher(self.logger)
        self.smoke_tester = SmokeTester(self.logger, self.docker)
        self.fixes_applied = []
    
    def validate_prerequisites(self) -> bool:
        """Check Docker is installed and running."""
        self.logger.info("Validating prerequisites...")
        
        if not check_docker_installed():
            self.logger.error("Docker is not installed")
            return False
        
        if not check_docker_running():
            self.logger.error("Docker daemon is not running")
            return False
        
        self.logger.success("Prerequisites validated")
        return True
    
    def generate_image_tag(self) -> str:
        """Generate image tag from git info or timestamp."""
        if self.args.tag != 'auto':
            return self.args.tag
        
        # Try to get git info
        try:
            result = subprocess.run(
                ['git', 'describe', '--tags', '--always'],
                capture_output=True,
                text=True,
                cwd=self.args.context
            )
            if result.returncode == 0:
                return f"pytorch-fsdp:{result.stdout.strip()}"
        except Exception:
            pass
        
        # Fallback to timestamp
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        return f"pytorch-fsdp:{timestamp}"
    
    def build_with_fixes(self, attempt: int) -> Tuple[bool, str]:
        """Build image with automatic fixes."""
        self.logger.section(f"Build Attempt {attempt}/{self.args.max_attempts}")
        
        # Create temporary directory for patched files
        temp_dir = tempfile.mkdtemp(prefix='docker-build-')
        
        try:
            # Copy context to temp directory
            context_temp = os.path.join(temp_dir, 'context')
            shutil.copytree(self.args.context, context_temp)
            
            # Analyze for conflicts
            dockerfile_path = os.path.join(context_temp, self.args.dockerfile)
            requirements_path = os.path.join(context_temp, 'src', 'requirements.txt')
            
            dockerfile_analysis = self.analyzer.analyze_dockerfile(dockerfile_path)
            requirements_analysis = self.analyzer.analyze_requirements(requirements_path)
            
            # Get fixes
            fixes = self.analyzer.get_fixes(
                dockerfile_analysis['issues'],
                requirements_analysis['issues']
            )
            
            # Apply fixes if auto_fix enabled
            if self.args.auto_fix and fixes:
                self.logger.info(f"Detected {len(fixes)} issues, applying fixes...")
                
                # Patch Dockerfile
                new_dockerfile = self.patcher.apply_fixes(dockerfile_path, fixes)
                with open(dockerfile_path, 'w') as f:
                    f.write(new_dockerfile)
                
                # Patch requirements.txt
                if os.path.exists(requirements_path):
                    new_requirements = self.patcher.patch_requirements(requirements_path, fixes)
                    with open(requirements_path, 'w') as f:
                        f.write(new_requirements)
                
                # Track fixes
                for fix in fixes:
                    if fix not in self.fixes_applied:
                        self.fixes_applied.append(fix)
            
            # Override base image if specified
            if self.args.base_image:
                with open(dockerfile_path, 'r') as f:
                    content = f.read()
                
                # Replace FROM line
                lines = content.split('\n')
                for i, line in enumerate(lines):
                    if line.strip().upper().startswith('FROM '):
                        lines[i] = f"FROM {self.args.base_image}"
                        break
                
                with open(dockerfile_path, 'w') as f:
                    f.write('\n'.join(lines))
                
                self.logger.info(f"Using specified base image: {self.args.base_image}")
            
            # Build image
            image_tag = self.generate_image_tag()
            self.logger.info(f"Building image: {image_tag}")
            
            success, output = self.docker.build(
                context=context_temp,
                tag=image_tag,
                dockerfile=self.args.dockerfile
            )
            
            if not success:
                self.logger.error("Build failed")
                self.logger.debug(output)
                return False, ""
            
            self.logger.success(f"Build successful: {image_tag}")
            return True, image_tag
            
        finally:
            # Cleanup temp directory
            shutil.rmtree(temp_dir, ignore_errors=True)
    
    def run(self) -> Dict:
        """Main build workflow."""
        start_time = datetime.now()
        
        self.logger.section("Docker Image Builder")
        self.logger.info(f"Dockerfile: {self.args.dockerfile}")
        self.logger.info(f"Context: {self.args.context}")
        self.logger.info(f"Auto-fix: {self.args.auto_fix}")
        self.logger.info(f"Max attempts: {self.args.max_attempts}")
        
        # Validate prerequisites
        if not self.validate_prerequisites():
            return {'success': False, 'error': 'Prerequisites not met'}
        
        # Build with retry
        final_image = None
        for attempt in range(1, self.args.max_attempts + 1):
            success, image_tag = self.build_with_fixes(attempt)
            
            if success:
                final_image = image_tag
                
                # Run smoke test
                smoke_success, smoke_output = self.smoke_tester.test_imports(image_tag)
                
                if smoke_success:
                    self.logger.success("Smoke test passed!")
                    break
                else:
                    self.logger.warning("Smoke test failed, will retry with fixes")
                    self.logger.debug(smoke_output)
                    
                    # Add smoke test failure to fixes for next attempt
                    if attempt < self.args.max_attempts:
                        self.logger.info("Analyzing smoke test failure for fixes...")
            else:
                if attempt >= self.args.max_attempts:
                    self.logger.error(f"All {self.args.max_attempts} attempts failed")
                    return {
                        'success': False,
                        'error': 'Max attempts reached',
                        'attempts': attempt,
                        'fixes_applied': self.fixes_applied
                    }
        
        # Calculate build time
        build_time = (datetime.now() - start_time).total_seconds()
        
        # Print summary
        self.logger.section("Build Summary")
        self.logger.success(f"Image: {final_image}")
        self.logger.info(f"Build time: {build_time:.1f}s")
        self.logger.info(f"Attempts: {attempt}")
        self.logger.info(f"Fixes applied: {len(self.fixes_applied)}")
        
        for fix in self.fixes_applied:
            self.logger.info(f"  - {fix.get('action', 'fix')}: {fix.get('reason', '')}")
        
        return {
            'success': True,
            'image_name': final_image,
            'build_time': f"{build_time:.1f}s",
            'attempts': attempt,
            'fixes_applied': self.fixes_applied
        }


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Build Docker image with auto-fix')
    parser.add_argument('--dockerfile', default='Dockerfile', help='Path to Dockerfile')
    parser.add_argument('--context', default='.', help='Build context path')
    parser.add_argument('--tag', default='auto', help='Image tag')
    parser.add_argument('--auto_fix', type=lambda x: x.lower() == 'true', default=True, help='Enable auto-fix')
    parser.add_argument('--max_attempts', type=int, default=3, help='Max rebuild attempts')
    parser.add_argument('--base_image', default='', help='Override base image')
    parser.add_argument('--verbose', type=lambda x: x.lower() == 'true', default=True, help='Verbose output')
    parser.add_argument('--use_sudo', type=lambda x: x.lower() == 'true', default=False, help='Use sudo')
    
    args = parser.parse_args()
    
    builder = ImageBuilder(args)
    result = builder.run()
    
    # Output result as JSON for parsing
    import json
    print(f"\nRESULT_JSON:{json.dumps(result)}")
    
    sys.exit(0 if result['success'] else 1)


if __name__ == '__main__':
    main()
