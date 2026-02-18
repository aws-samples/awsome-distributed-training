#!/usr/bin/env python3
"""
Docker Image Builder - Unified Entry Point

Automatically detects whether Docker is available locally:
  - If Docker is available: builds locally with conflict analysis, auto-fix, and smoke tests
  - If Docker is NOT available: falls back to AWS CodeBuild (warns about charges)

Usage:
  python3 build_image.py                          # Auto-detect mode
  python3 build_image.py --force-local             # Force local Docker
  python3 build_image.py --force-codebuild         # Force CodeBuild
  python3 build_image.py --context ./FSDP          # Specify build context
"""

import argparse
import sys
import os
import subprocess
import tempfile
import shutil
import zipfile
import json
import time
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Tuple

# Add shared utilities to path - look in multiple locations
_shared_paths = [
    os.path.join(os.path.dirname(__file__), '..', '..', 'shared'),
    os.path.expanduser('~/.opencode/skills/shared'),
    os.path.expanduser('~/.config/opencode/skills/shared'),
]
for _p in _shared_paths:
    _resolved = os.path.abspath(_p)
    if os.path.isdir(_resolved) and _resolved not in sys.path:
        sys.path.insert(0, _resolved)

from logger import create_logger, StatusReporter
from docker_utils import (
    DockerClient, parse_dockerfile, analyze_base_image_compatibility,
    get_recommended_base_image, check_docker_installed, check_docker_running
)


# =============================================================================
# Conflict Analysis & Auto-Fix (used by both local and CodeBuild paths)
# =============================================================================

class ConflictAnalyzer:
    """Analyzes Dockerfile and requirements for conflicts."""

    def __init__(self, logger):
        self.logger = logger

    def analyze_dockerfile(self, dockerfile_path: str) -> Dict:
        """Analyze Dockerfile for issues."""
        self.logger.info(f"Analyzing Dockerfile: {dockerfile_path}")

        dockerfile_info = parse_dockerfile(dockerfile_path)
        issues = []

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

        return {'info': dockerfile_info, 'issues': issues}

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
                if '==' in line:
                    pkg, ver = line.split('==', 1)
                    packages[pkg.lower()] = ver

        # Check for known conflicts
        torch_ver = packages.get('torch', '')
        torchvision_ver = packages.get('torchvision', '')

        if torch_ver and torchvision_ver:
            if torch_ver.startswith(('2.7', '2.6')):
                if not torchvision_ver.startswith(('0.22', '0.21')):
                    issues.append({
                        'type': 'version_conflict',
                        'severity': 'warning',
                        'message': f'torch=={torch_ver} may conflict with torchvision=={torchvision_ver}',
                        'suggested_action': 'Remove torchvision or update to compatible version'
                    })

        return {'packages': packages, 'issues': issues}

    def get_fixes(self, dockerfile_issues: List[Dict], requirements_issues: List[Dict]) -> List[Dict]:
        """Generate list of fixes to apply."""
        fixes = []

        for issue in dockerfile_issues:
            if issue['type'] == 'base_image_compatibility':
                fixes.append({
                    'file': 'Dockerfile',
                    'action': 'replace_base_image',
                    'old': issue['current'],
                    'new': issue['suggested'],
                    'reason': issue['message']
                })

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
    """Patches Dockerfile and requirements with fixes."""

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
                self.logger.info(f"Fixing: Replacing base image {fix['old']} -> {fix['new']}")
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
                        self.logger.info(f"Fixing: Removing {fix['package']} ({fix['reason']})")
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
    print(f"PyTorch: {torch.__version__}")
except ImportError as e:
    print(f"PyTorch import failed: {e}")
    sys.exit(1)

try:
    import transformers
    print(f"Transformers: {transformers.__version__}")
except ImportError as e:
    print(f"Transformers import failed: {e}")
    sys.exit(1)

try:
    import datasets
    print(f"Datasets: {datasets.__version__}")
except ImportError as e:
    print(f"Datasets import failed: {e}")
    sys.exit(1)

print("All imports successful!")
"""

        success, output = self.docker.run(
            image_name,
            command=['python', '-c', test_script]
        )

        return success, output


# =============================================================================
# CodeBuild Manager (S3 upload, trigger, wait)
# =============================================================================

class CodeBuildManager:
    """Manages CodeBuild builds with S3 source."""

    def __init__(self, logger, region: str = "us-west-2"):
        self.logger = logger
        self.region = region

    def check_codebuild_project(self, project_name: str) -> Tuple[bool, str]:
        """Check if CodeBuild project exists."""
        try:
            result = subprocess.run(
                ['aws', 'codebuild', 'batch-get-projects',
                 '--names', project_name,
                 '--region', self.region,
                 '--query', 'projects[0].name',
                 '--output', 'text'],
                capture_output=True, text=True, timeout=30
            )
            if result.returncode == 0 and project_name in result.stdout:
                return True, f"Project '{project_name}' exists"
            else:
                return False, f"Project '{project_name}' not found"
        except Exception as e:
            return False, str(e)

    def create_s3_bucket(self, bucket_name: str) -> Tuple[bool, str]:
        """Create S3 bucket for source code (if needed)."""
        try:
            result = subprocess.run(
                ['aws', 's3api', 'head-bucket',
                 '--bucket', bucket_name,
                 '--region', self.region],
                capture_output=True, timeout=10
            )
            if result.returncode == 0:
                return True, f"Bucket '{bucket_name}' already exists"

            result = subprocess.run(
                ['aws', 's3', 'mb', f's3://{bucket_name}',
                 '--region', self.region],
                capture_output=True, text=True, timeout=30
            )
            if result.returncode == 0:
                return True, f"Created bucket: {bucket_name}"
            else:
                return False, result.stderr
        except Exception as e:
            return False, str(e)

    def upload_source_to_s3(self, context_path: str, bucket_name: str,
                            key: str = "source/source.zip") -> Tuple[bool, str]:
        """Upload source code to S3 as a zip."""
        try:
            temp_dir = tempfile.mkdtemp()
            zip_path = os.path.join(temp_dir, 'source.zip')

            self.logger.info(f"Creating source zip from: {context_path}")

            with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
                for root, dirs, files in os.walk(context_path):
                    dirs[:] = [d for d in dirs if d not in [
                        '.git', '__pycache__', '.pytest_cache',
                        'node_modules', '.venv', 'venv'
                    ]]
                    for file in files:
                        if file.endswith(('.pyc', '.pyo', '.DS_Store')):
                            continue
                        file_path = os.path.join(root, file)
                        arc_name = os.path.relpath(file_path, context_path)
                        zipf.write(file_path, arc_name)

            s3_uri = f"s3://{bucket_name}/{key}"
            self.logger.info(f"Uploading to {s3_uri}")

            result = subprocess.run(
                ['aws', 's3', 'cp', zip_path, s3_uri,
                 '--region', self.region],
                capture_output=True, text=True, timeout=120
            )

            shutil.rmtree(temp_dir, ignore_errors=True)

            if result.returncode == 0:
                return True, s3_uri
            else:
                return False, result.stderr
        except Exception as e:
            return False, str(e)

    def trigger_codebuild(self, project_name: str,
                          source_location: Optional[str] = None) -> Tuple[bool, str, Optional[str]]:
        """Trigger CodeBuild with S3 source."""
        try:
            cmd = [
                'aws', 'codebuild', 'start-build',
                '--project-name', project_name,
                '--region', self.region
            ]
            if source_location:
                cmd.extend(['--source-location-override', source_location])

            self.logger.info(f"Triggering CodeBuild project: {project_name}")

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

            if result.returncode == 0:
                build_info = json.loads(result.stdout)
                build_id = build_info.get('build', {}).get('id', 'unknown')
                return True, f"Build triggered: {build_id}", build_id
            else:
                return False, result.stderr, None
        except Exception as e:
            return False, str(e), None

    def wait_for_build(self, build_id: str, timeout: int = 3600) -> Tuple[bool, str]:
        """Wait for build to complete."""
        self.logger.info(f"Waiting for build: {build_id}")
        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                result = subprocess.run(
                    ['aws', 'codebuild', 'batch-get-builds',
                     '--ids', build_id,
                     '--region', self.region,
                     '--query', 'builds[0].{status:buildStatus,phase:currentPhase}',
                     '--output', 'json'],
                    capture_output=True, text=True, timeout=10
                )

                if result.returncode == 0:
                    build_status = json.loads(result.stdout)
                    status = build_status.get('status', 'UNKNOWN')
                    phase = build_status.get('phase', 'UNKNOWN')

                    self.logger.info(f"Build status: {status}, Phase: {phase}")

                    if status == 'SUCCEEDED':
                        return True, "Build completed successfully"
                    elif status in ['FAILED', 'STOPPED', 'TIMED_OUT']:
                        return False, f"Build {status.lower()}"

                    time.sleep(30)
                else:
                    time.sleep(10)
            except Exception as e:
                self.logger.warning(f"Error checking build status: {e}")
                time.sleep(10)

        return False, "Build timeout"

    def get_build_logs(self, build_id: str, tail: int = 50) -> str:
        """Get build logs from CloudWatch."""
        try:
            log_stream = build_id.split(':')[-1]
            log_group = f"/aws/codebuild/{build_id.split(':')[0]}"

            result = subprocess.run(
                ['aws', 'logs', 'get-log-events',
                 '--log-group-name', log_group,
                 '--log-stream-name', log_stream,
                 '--region', self.region,
                 '--limit', str(tail),
                 '--query', 'events[*].message',
                 '--output', 'text'],
                capture_output=True, text=True, timeout=30
            )

            if result.returncode == 0:
                return result.stdout
            else:
                return f"Error retrieving logs: {result.stderr}"
        except Exception as e:
            return f"Error: {str(e)}"


# =============================================================================
# Unified Image Builder
# =============================================================================

class ImageBuilder:
    """
    Unified image builder.

    Auto-detection logic:
      1. If --force-local: use local Docker (fail if not available)
      2. If --force-codebuild: use CodeBuild (warn about charges)
      3. Otherwise: try local Docker first, fall back to CodeBuild
    """

    def __init__(self, args):
        self.args = args
        self.logger = create_logger('docker-image-builder', verbose=args.verbose)
        self.reporter = StatusReporter(self.logger)
        self.analyzer = ConflictAnalyzer(self.logger)
        self.patcher = DockerfilePatcher(self.logger)
        self.fixes_applied = []

    # ---- Detection ----

    def _docker_available(self) -> bool:
        """Check if Docker is installed and running."""
        return check_docker_installed() and check_docker_running()

    def _aws_cli_available(self) -> bool:
        """Check if AWS CLI is installed and credentials are configured."""
        try:
            r = subprocess.run(['aws', '--version'], capture_output=True, timeout=5)
            if r.returncode != 0:
                return False
            r = subprocess.run(['aws', 'sts', 'get-caller-identity'],
                               capture_output=True, timeout=10)
            return r.returncode == 0
        except Exception:
            return False

    def detect_build_mode(self) -> str:
        """
        Detect whether to use local Docker or CodeBuild.

        Returns: 'local' or 'codebuild'
        """
        if self.args.force_local:
            if not self._docker_available():
                self.logger.error("--force-local specified but Docker is not available")
                sys.exit(1)
            return 'local'

        if self.args.force_codebuild:
            if not self._aws_cli_available():
                self.logger.error("--force-codebuild specified but AWS CLI/credentials not available")
                sys.exit(1)
            return 'codebuild'

        # Auto-detect: prefer local Docker
        if self._docker_available():
            self.logger.info("Docker detected locally - using local build")
            return 'local'

        # Fall back to CodeBuild
        if self._aws_cli_available():
            self.logger.warning("=" * 60)
            self.logger.warning("Docker not available locally. Falling back to AWS CodeBuild.")
            self.logger.warning("NOTE: CodeBuild builds may incur AWS charges (~$0.10/build).")
            self.logger.warning("Use --force-local to require local Docker instead.")
            self.logger.warning("=" * 60)
            return 'codebuild'

        self.logger.error("Neither Docker nor AWS CLI/credentials are available.")
        self.logger.error("Install Docker for local builds, or configure AWS CLI for CodeBuild.")
        sys.exit(1)

    # ---- Conflict analysis + patching (shared by both paths) ----

    def _analyze_and_fix(self, context_dir: str) -> List[Dict]:
        """Run conflict analysis and apply fixes in the given context directory."""
        dockerfile_path = os.path.join(context_dir, self.args.dockerfile)
        # Look for requirements.txt in common locations
        requirements_path = None
        for candidate in ['src/requirements.txt', 'requirements.txt']:
            p = os.path.join(context_dir, candidate)
            if os.path.exists(p):
                requirements_path = p
                break

        dockerfile_analysis = self.analyzer.analyze_dockerfile(dockerfile_path)
        requirements_analysis = (
            self.analyzer.analyze_requirements(requirements_path)
            if requirements_path else {'packages': [], 'issues': []}
        )

        fixes = self.analyzer.get_fixes(
            dockerfile_analysis['issues'],
            requirements_analysis.get('issues', [])
        )

        if not self.args.auto_fix:
            if fixes:
                self.logger.warning(f"Detected {len(fixes)} issues (auto-fix disabled):")
                for fix in fixes:
                    self.logger.warning(f"  - {fix.get('action')}: {fix.get('reason')}")
            return []

        if fixes:
            self.logger.info(f"Detected {len(fixes)} issues, applying fixes...")

            new_dockerfile = self.patcher.apply_fixes(dockerfile_path, fixes)
            with open(dockerfile_path, 'w') as f:
                f.write(new_dockerfile)

            if requirements_path:
                new_requirements = self.patcher.patch_requirements(requirements_path, fixes)
                with open(requirements_path, 'w') as f:
                    f.write(new_requirements)

            self.fixes_applied.extend(fixes)

        return fixes

    # ---- Local Docker build ----

    def build_local(self) -> Dict:
        """Build image using local Docker with conflict analysis + auto-fix + smoke tests."""
        start_time = datetime.now()
        docker = DockerClient(use_sudo=self.args.use_sudo)
        smoke_tester = SmokeTester(self.logger, docker)

        self.logger.section("Local Docker Build")
        self.logger.info(f"Dockerfile: {self.args.dockerfile}")
        self.logger.info(f"Context: {self.args.context}")
        self.logger.info(f"Auto-fix: {self.args.auto_fix}")
        self.logger.info(f"Max attempts: {self.args.max_attempts}")

        final_image = None
        attempt = 0

        for attempt in range(1, self.args.max_attempts + 1):
            self.logger.section(f"Build Attempt {attempt}/{self.args.max_attempts}")

            # Create temp directory with patched files
            temp_dir = tempfile.mkdtemp(prefix='docker-build-')
            try:
                context_temp = os.path.join(temp_dir, 'context')
                shutil.copytree(self.args.context, context_temp)

                # Analyze and fix
                self._analyze_and_fix(context_temp)

                # Override base image if specified
                if self.args.base_image:
                    dockerfile_path = os.path.join(context_temp, self.args.dockerfile)
                    with open(dockerfile_path, 'r') as f:
                        content = f.read()
                    lines = content.split('\n')
                    for i, line in enumerate(lines):
                        if line.strip().upper().startswith('FROM '):
                            lines[i] = f"FROM {self.args.base_image}"
                            break
                    with open(dockerfile_path, 'w') as f:
                        f.write('\n'.join(lines))
                    self.logger.info(f"Using specified base image: {self.args.base_image}")

                # Build image
                image_tag = self._generate_image_tag()
                self.logger.info(f"Building image: {image_tag}")

                success, output = docker.build(
                    context=context_temp,
                    tag=image_tag,
                    dockerfile=self.args.dockerfile
                )

                if not success:
                    self.logger.error("Build failed")
                    self.logger.debug(output)
                    if attempt >= self.args.max_attempts:
                        return {
                            'success': False,
                            'error': 'Max attempts reached',
                            'mode': 'local',
                            'attempts': attempt,
                            'fixes_applied': self.fixes_applied
                        }
                    continue

                self.logger.success(f"Build successful: {image_tag}")
                final_image = image_tag

                # Smoke test
                if self.args.smoke_test:
                    smoke_ok, smoke_out = smoke_tester.test_imports(image_tag)
                    if smoke_ok:
                        self.logger.success("Smoke test passed!")
                        break
                    else:
                        self.logger.warning("Smoke test failed, will retry with fixes")
                        self.logger.debug(smoke_out)
                        if attempt >= self.args.max_attempts:
                            break
                else:
                    break

            finally:
                shutil.rmtree(temp_dir, ignore_errors=True)

        build_time = (datetime.now() - start_time).total_seconds()

        self.logger.section("Build Summary")
        self.logger.success(f"Image: {final_image}")
        self.logger.info(f"Build time: {build_time:.1f}s")
        self.logger.info(f"Attempts: {attempt}")
        self.logger.info(f"Fixes applied: {len(self.fixes_applied)}")
        for fix in self.fixes_applied:
            self.logger.info(f"  - {fix.get('action', 'fix')}: {fix.get('reason', '')}")

        return {
            'success': final_image is not None,
            'image_name': final_image,
            'mode': 'local',
            'build_time': f"{build_time:.1f}s",
            'attempts': attempt,
            'fixes_applied': self.fixes_applied
        }

    # ---- CodeBuild build ----

    def build_codebuild(self) -> Dict:
        """Build image using CodeBuild with S3 source."""
        start_time = datetime.now()
        codebuild = CodeBuildManager(self.logger, region=self.args.region)

        self.logger.section("CodeBuild Build")

        project_name = self.args.codebuild_project
        # Derive bucket name from account ID if possible
        bucket_name = self.args.s3_bucket
        if not bucket_name:
            try:
                result = subprocess.run(
                    ['aws', 'sts', 'get-caller-identity',
                     '--query', 'Account', '--output', 'text'],
                    capture_output=True, text=True, timeout=10
                )
                account_id = result.stdout.strip() if result.returncode == 0 else None
            except Exception:
                account_id = None
            bucket_name = f"{project_name}-build-artifacts"
            if account_id:
                bucket_name = f"{project_name}-build-artifacts-{account_id}"

        # Check project exists
        exists, msg = codebuild.check_codebuild_project(project_name)
        if not exists:
            self.logger.error(f"CodeBuild project not found: {project_name}")
            self.logger.info("Create it first:")
            self.logger.info(f"  ./opencode/skills/infrastructure/aws-cli/setup-codebuild.sh \\")
            self.logger.info(f"    --project-name {project_name}")
            return {'success': False, 'error': msg, 'mode': 'codebuild', 'attempts': 0, 'fixes_applied': []}

        self.logger.success(f"Found CodeBuild project: {project_name}")

        # Pre-build: run conflict analysis on source before uploading
        if self.args.auto_fix:
            self.logger.info("Running conflict analysis before uploading to CodeBuild...")
            temp_dir = tempfile.mkdtemp(prefix='codebuild-prep-')
            try:
                context_temp = os.path.join(temp_dir, 'context')
                shutil.copytree(self.args.context, context_temp)
                fixes = self._analyze_and_fix(context_temp)

                if fixes:
                    # Use the patched context for upload
                    self.logger.info(f"Applied {len(fixes)} fixes before uploading to CodeBuild")
                    upload_context = context_temp
                else:
                    upload_context = self.args.context
            except Exception as e:
                self.logger.warning(f"Conflict analysis failed, uploading original source: {e}")
                upload_context = self.args.context
                temp_dir = None
        else:
            upload_context = self.args.context
            temp_dir = None

        try:
            # Ensure S3 bucket exists
            success, msg = codebuild.create_s3_bucket(bucket_name)
            if not success:
                self.logger.error(f"Failed to create S3 bucket: {msg}")
                return {'success': False, 'error': msg, 'mode': 'codebuild', 'attempts': 0, 'fixes_applied': self.fixes_applied}
            self.logger.success(msg)

            # Upload source
            success, msg = codebuild.upload_source_to_s3(upload_context, bucket_name, "source/source.zip")
            if not success:
                self.logger.error(f"Failed to upload source: {msg}")
                return {'success': False, 'error': msg, 'mode': 'codebuild', 'attempts': 0, 'fixes_applied': self.fixes_applied}

            s3_uri = msg
            self.logger.success(f"Source uploaded to: {s3_uri}")

            # Trigger build
            success, msg, build_id = codebuild.trigger_codebuild(project_name, source_location=s3_uri)
            if not success or build_id is None:
                self.logger.error(f"Failed to trigger build: {msg}")
                return {'success': False, 'error': msg, 'mode': 'codebuild', 'attempts': 0, 'fixes_applied': self.fixes_applied}

            self.logger.success(msg)

            # Wait for build
            if self.args.wait:
                self.logger.info("Waiting for build to complete...")
                success, msg = codebuild.wait_for_build(build_id, timeout=self.args.timeout)

                if not success:
                    self.logger.error(f"Build failed: {msg}")
                    logs = codebuild.get_build_logs(build_id)
                    self.logger.info("Build logs (last 50 lines):")
                    print(logs)
                    return {
                        'success': False,
                        'error': msg,
                        'mode': 'codebuild',
                        'build_id': build_id,
                        'attempts': 1,
                        'fixes_applied': self.fixes_applied
                    }

                build_time = (datetime.now() - start_time).total_seconds()
                image_full = f"{self.args.image_name}:{self.args.image_tag}"
                self.logger.success(f"Build completed! Image: {image_full}")
                self.logger.info(f"Build time: {build_time:.1f}s")
                return {
                    'success': True,
                    'image_name': image_full,
                    'mode': 'codebuild',
                    'build_id': build_id,
                    'build_time': f"{build_time:.1f}s",
                    'attempts': 1,
                    'fixes_applied': self.fixes_applied
                }
            else:
                self.logger.info("Build triggered in background")
                self.logger.info(f"Monitor with: aws codebuild batch-get-builds --ids {build_id}")
                image_full = f"{self.args.image_name}:{self.args.image_tag}"
                return {
                    'success': True,
                    'image_name': image_full,
                    'mode': 'codebuild',
                    'build_id': build_id,
                    'build_time': 'N/A (background)',
                    'attempts': 1,
                    'fixes_applied': self.fixes_applied
                }
        finally:
            if temp_dir:
                shutil.rmtree(temp_dir, ignore_errors=True)

    # ---- Helpers ----

    def _generate_image_tag(self) -> str:
        """Generate image tag from git info or timestamp."""
        if self.args.image_tag != 'auto':
            name = self.args.image_name or 'pytorch-fsdp'
            return f"{name}:{self.args.image_tag}"

        # Try git
        try:
            result = subprocess.run(
                ['git', 'describe', '--tags', '--always'],
                capture_output=True, text=True, cwd=self.args.context
            )
            if result.returncode == 0:
                name = self.args.image_name or 'pytorch-fsdp'
                return f"{name}:{result.stdout.strip()}"
        except Exception:
            pass

        # Fallback to timestamp
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        name = self.args.image_name or 'pytorch-fsdp'
        return f"{name}:{timestamp}"

    # ---- Main entry ----

    def run(self) -> Dict:
        """Main entry point - detect mode and build."""
        mode = self.detect_build_mode()

        if mode == 'local':
            return self.build_local()
        else:
            return self.build_codebuild()


# =============================================================================
# CLI
# =============================================================================

def get_default_image_name() -> str:
    """Get default image name from current directory."""
    current_dir = os.path.basename(os.getcwd())
    clean_name = ''.join(c if c.isalnum() or c == '-' else '-' for c in current_dir.lower())
    clean_name = clean_name.strip('-')
    return clean_name or 'docker-image'


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Build Docker images - auto-detects local Docker or falls back to CodeBuild',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Auto-detect (local Docker preferred, CodeBuild fallback)
  python3 build_image.py --context ./FSDP

  # Force local Docker
  python3 build_image.py --force-local --context ./FSDP

  # Force CodeBuild
  python3 build_image.py --force-codebuild --codebuild-project pytorch-fsdp

  # Custom image name and tag
  python3 build_image.py --image-name fsdp --image-tag v1.0.0
"""
    )

    # Build mode (mutually exclusive)
    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument('--force-local', action='store_true',
                            help='Force local Docker build (fail if Docker not available)')
    mode_group.add_argument('--force-codebuild', action='store_true',
                            help='Force CodeBuild build (warn about charges)')

    # Source options
    parser.add_argument('--context', default='.',
                        help='Build context path (default: .)')
    parser.add_argument('--dockerfile', default='Dockerfile',
                        help='Path to Dockerfile relative to context (default: Dockerfile)')

    # Image naming
    default_image = get_default_image_name()
    parser.add_argument('--image-name', default=default_image,
                        help=f'Image name (default: "{default_image}")')
    parser.add_argument('--image-tag', default='latest',
                        help='Image tag (default: latest)')

    # Auto-fix options
    parser.add_argument('--auto-fix', dest='auto_fix', action='store_true', default=True,
                        help='Automatically fix detected conflicts (default: true)')
    parser.add_argument('--no-auto-fix', dest='auto_fix', action='store_false',
                        help='Disable auto-fix')
    parser.add_argument('--smoke-test', dest='smoke_test', action='store_true', default=True,
                        help='Run smoke tests after local build (default: true)')
    parser.add_argument('--no-smoke-test', dest='smoke_test', action='store_false',
                        help='Skip smoke tests')

    # Local Docker options
    parser.add_argument('--max-attempts', type=int, default=3,
                        help='Max rebuild attempts for local builds (default: 3)')
    parser.add_argument('--base-image', default='',
                        help='Override base image (default: auto-detect)')
    parser.add_argument('--use-sudo', action='store_true', default=False,
                        help='Use sudo for Docker commands')

    # CodeBuild options
    parser.add_argument('--codebuild-project', default='pytorch-fsdp',
                        help='CodeBuild project name (default: pytorch-fsdp)')
    parser.add_argument('--s3-bucket', default=None,
                        help='S3 bucket for source code (auto-generated if not specified)')
    parser.add_argument('--region', default='us-west-2',
                        help='AWS region (default: us-west-2)')
    parser.add_argument('--wait', action='store_true', default=True,
                        help='Wait for CodeBuild completion (default: true)')
    parser.add_argument('--no-wait', dest='wait', action='store_false',
                        help='Trigger CodeBuild in background')
    parser.add_argument('--timeout', type=int, default=3600,
                        help='CodeBuild timeout in seconds (default: 3600)')

    # Output
    parser.add_argument('--verbose', action='store_true', default=True,
                        help='Verbose output (default: true)')
    parser.add_argument('--quiet', dest='verbose', action='store_false',
                        help='Minimal output')

    args = parser.parse_args()

    builder = ImageBuilder(args)
    result = builder.run()

    # Output result as JSON for parsing
    print(f"\nRESULT_JSON:{json.dumps(result)}")

    sys.exit(0 if result.get('success') else 1)


if __name__ == '__main__':
    main()
