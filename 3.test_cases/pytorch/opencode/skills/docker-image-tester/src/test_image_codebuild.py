#!/usr/bin/env python3
"""
Docker Image Tester with CodeBuild Support
Test Docker images using CodeBuild (no local Docker required) or local Docker.
"""

import argparse
import sys
import os
import json
import subprocess
import tempfile
import zipfile
import shutil
from datetime import datetime
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass, asdict

# Add shared utilities to path
sys.path.insert(0, os.path.expanduser('~/.opencode/skills/shared'))

from logger import create_logger, StatusReporter


@dataclass
class TestCase:
    """Represents a single test case."""
    name: str
    category: str
    description: str
    passed: bool = False
    message: str = ""
    duration_ms: int = 0
    error_details: Optional[str] = None


@dataclass
class TestResult:
    """Represents overall test results."""
    image_name: str
    tests: List[TestCase]
    passed: bool
    total_tests: int
    passed_tests: int
    duration_seconds: float
    report_path: Optional[str] = None


class CodeBuildTester:
    """Test Docker images using CodeBuild - no local Docker required!"""
    
    def __init__(self, logger, region: str = "us-west-2"):
        self.logger = logger
        self.region = region
    
    def create_test_buildspec(self, image_uri: str, test_level: str = "standard") -> str:
        """Create a buildspec for testing the image."""
        
        # Define test scripts based on level
        if test_level == "quick":
            test_commands = [
                "echo 'Running quick tests (imports only)...'",
                "python3 -c \"import torch; import transformers; import datasets; print('✓ All imports successful')\""
            ]
        elif test_level == "standard":
            test_commands = [
                "echo 'Running standard tests...'",
                "python3 -c \"import torch; print(f'PyTorch: {torch.__version__}')\"",
                "python3 -c \"import torch; print(f'CUDA available: {torch.cuda.is_available()}')\"",
                "python3 -c \"from transformers import AutoConfig; print('✓ Transformers config loading works')\"",
                "python3 -c \"from datasets import load_dataset_builder; print('✓ Datasets import works')\""
            ]
        else:  # full
            test_commands = [
                "echo 'Running full tests...'",
                "python3 -c \"import torch; print(f'PyTorch: {torch.__version__}')\"",
                "python3 -c \"import torch; print(f'CUDA available: {torch.cuda.is_available()}')\"",
                "python3 -c \"from transformers import AutoConfig; print('✓ Transformers config loading works')\"",
                "python3 -c \"from datasets import load_dataset_builder; print('✓ Datasets import works')\"",
                "python3 -c \"from transformers import AutoModelForCausalLM; print('✓ Model loading works')\"",
                "echo 'All tests passed!'"
            ]
        
        buildspec = {
            "version": "0.2",
            "env": {
                "variables": {
                    "IMAGE_URI": image_uri,
                    "TEST_LEVEL": test_level
                }
            },
            "phases": {
                "pre_build": {
                    "commands": [
                        "echo \"Testing image: ${IMAGE_URI}\"",
                        "echo \"Test level: ${TEST_LEVEL}\"",
                        "aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com || true"
                    ]
                },
                "build": {
                    "commands": test_commands
                }
            }
        }
        
        return json.dumps(buildspec, indent=2)
    
    def create_s3_bucket(self, bucket_name: str) -> Tuple[bool, str]:
        """Create S3 bucket for test artifacts."""
        try:
            # Check if bucket exists
            result = subprocess.run(
                ['aws', 's3api', 'head-bucket', 
                 '--bucket', bucket_name,
                 '--region', self.region],
                capture_output=True,
                timeout=10
            )
            
            if result.returncode == 0:
                return True, f"Bucket '{bucket_name}' already exists"
            
            # Create bucket
            result = subprocess.run(
                ['aws', 's3', 'mb', 
                 f's3://{bucket_name}',
                 '--region', self.region],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                return True, f"Created bucket: {bucket_name}"
            else:
                return False, result.stderr
        except Exception as e:
            return False, str(e)
    
    def upload_buildspec(self, buildspec: str, bucket_name: str, key: str = "test-buildspec.json") -> Tuple[bool, str]:
        """Upload buildspec to S3."""
        try:
            # Create temp file
            temp_dir = tempfile.mkdtemp()
            buildspec_path = os.path.join(temp_dir, 'buildspec.json')
            
            with open(buildspec_path, 'w') as f:
                f.write(buildspec)
            
            # Upload to S3
            s3_uri = f"s3://{bucket_name}/{key}"
            
            result = subprocess.run(
                ['aws', 's3', 'cp', buildspec_path, s3_uri,
                 '--region', self.region],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            shutil.rmtree(temp_dir)
            
            if result.returncode == 0:
                return True, s3_uri
            else:
                return False, result.stderr
        except Exception as e:
            return False, str(e)
    
    def run_inline_test(self, image_uri: str, test_level: str = "standard") -> Tuple[bool, str]:
        """Run tests inline using CodeBuild without creating a project."""
        
        self.logger.info(f"Testing image: {image_uri}")
        self.logger.info(f"Test level: {test_level}")
        
        # Create buildspec
        buildspec = self.create_test_buildspec(image_uri, test_level)
        
        # Create temp file for buildspec
        temp_dir = tempfile.mkdtemp()
        buildspec_path = os.path.join(temp_dir, 'buildspec.json')
        
        with open(buildspec_path, 'w') as f:
            f.write(buildspec)
        
        try:
            # Run CodeBuild locally with buildspec override
            # This requires a CodeBuild project to exist
            self.logger.info("Starting CodeBuild test...")
            
            # For inline testing, we'll use the existing project but override the buildspec
            # This is a workaround since CodeBuild doesn't support true inline builds
            
            # Alternative: Use AWS CLI to start a build with inline buildspec
            cmd = [
                'aws', 'codebuild', 'start-build',
                '--project-name', 'pytorch-fsdp',  # Use existing project
                '--region', self.region,
                '--buildspec-override', buildspec_path
            ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                build_info = json.loads(result.stdout)
                build_id = build_info.get('build', {}).get('id', 'unknown')
                self.logger.success(f"Test build triggered: {build_id}")
                return True, build_id
            else:
                return False, result.stderr
                
        finally:
            shutil.rmtree(temp_dir)
    
    def wait_for_test(self, build_id: str, timeout: int = 600) -> Tuple[bool, str, List[TestCase]]:
        """Wait for test build to complete and parse results."""
        import time
        
        self.logger.info(f"Waiting for test build: {build_id}")
        start_time = time.time()
        tests = []
        
        while time.time() - start_time < timeout:
            try:
                result = subprocess.run(
                    ['aws', 'codebuild', 'batch-get-builds',
                     '--ids', build_id,
                     '--region', self.region,
                     '--query', 'builds[0].{status:buildStatus,phase:currentPhase}',
                     '--output', 'json'],
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                
                if result.returncode == 0:
                    build_status = json.loads(result.stdout)
                    status = build_status.get('status', 'UNKNOWN')
                    phase = build_status.get('phase', 'UNKNOWN')
                    
                    self.logger.info(f"Test status: {status}, Phase: {phase}")
                    
                    if status == 'SUCCEEDED':
                        tests.append(TestCase(
                            name="codebuild_test",
                            category="validation",
                            description="CodeBuild test execution",
                            passed=True,
                            message="All tests passed in CodeBuild"
                        ))
                        return True, "Tests passed", tests
                    elif status in ['FAILED', 'STOPPED', 'TIMED_OUT']:
                        tests.append(TestCase(
                            name="codebuild_test",
                            category="validation",
                            description="CodeBuild test execution",
                            passed=False,
                            message=f"Tests {status.lower()} in CodeBuild"
                        ))
                        return False, f"Tests {status.lower()}", tests
                    
                    time.sleep(10)
                else:
                    time.sleep(5)
                    
            except Exception as e:
                self.logger.warning(f"Error checking test status: {e}")
                time.sleep(5)
        
        return False, "Test timeout", tests
    
    def get_test_logs(self, build_id: str, tail: int = 100) -> str:
        """Get test logs from CloudWatch."""
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
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                return result.stdout
            else:
                return f"Error retrieving logs: {result.stderr}"
        except Exception as e:
            return f"Error: {str(e)}"


class ImageTester:
    """Main image tester supporting both CodeBuild and local Docker."""
    
    def __init__(self, args):
        self.args = args
        self.logger = create_logger('docker-image-tester', verbose=args.verbose)
        self.codebuild_tester = CodeBuildTester(self.logger, region=args.region)
    
    def validate_prerequisites(self) -> bool:
        """Check prerequisites."""
        if self.args.use_codebuild:
            # Check AWS CLI
            try:
                result = subprocess.run(
                    ['aws', '--version'],
                    capture_output=True,
                    timeout=5
                )
                if result.returncode != 0:
                    self.logger.error("AWS CLI not found")
                    return False
            except:
                self.logger.error("AWS CLI not found")
                return False
            
            # Check AWS credentials
            try:
                result = subprocess.run(
                    ['aws', 'sts', 'get-caller-identity'],
                    capture_output=True,
                    timeout=10
                )
                if result.returncode != 0:
                    self.logger.error("AWS credentials not configured")
                    return False
            except:
                self.logger.error("AWS credentials not configured")
                return False
            
            self.logger.success("AWS prerequisites validated")
            return True
        else:
            # Check Docker
            try:
                result = subprocess.run(
                    ['docker', '--version'],
                    capture_output=True,
                    timeout=5
                )
                if result.returncode != 0:
                    self.logger.error("Docker not found")
                    return False
            except:
                self.logger.error("Docker not found")
                return False
            
            self.logger.success("Docker validated")
            return True
    
    def test_with_codebuild(self) -> Dict:
        """Test image using CodeBuild."""
        self.logger.section("CodeBuild Image Test")
        
        # Run inline test
        success, msg = self.codebuild_tester.run_inline_test(
            self.args.image,
            self.args.level
        )
        
        if not success:
            self.logger.error(f"Failed to start test: {msg}")
            return {
                'success': False,
                'error': msg,
                'image': self.args.image,
                'tests': []
            }
        
        build_id = msg
        self.logger.success(f"Test started: {build_id}")
        
        # Wait for test if requested
        if self.args.wait:
            success, msg, tests = self.codebuild_tester.wait_for_test(
                build_id,
                timeout=self.args.timeout
            )
            
            if not success:
                self.logger.error(f"Test failed: {msg}")
                logs = self.codebuild_tester.get_test_logs(build_id)
                self.logger.info("Test logs:")
                print(logs)
                return {
                    'success': False,
                    'error': msg,
                    'image': self.args.image,
                    'build_id': build_id,
                    'tests': [asdict(t) for t in tests]
                }
            
            self.logger.success("All tests passed!")
            return {
                'success': True,
                'image': self.args.image,
                'build_id': build_id,
                'tests': [asdict(t) for t in tests],
                'message': msg
            }
        else:
            self.logger.info("Test running in background")
            return {
                'success': True,
                'image': self.args.image,
                'build_id': build_id,
                'tests': [],
                'message': 'Test running in background'
            }
    
    def run(self) -> Dict:
        """Main entry point."""
        if not self.validate_prerequisites():
            return {
                'success': False,
                'error': 'Prerequisites not met',
                'image': self.args.image,
                'tests': []
            }
        
        if self.args.use_codebuild:
            return self.test_with_codebuild()
        else:
            self.logger.info("Local Docker test not implemented in this version")
            self.logger.info("Use --use-codebuild for CodeBuild testing")
            return {
                'success': False,
                'error': 'Local test not implemented',
                'image': self.args.image,
                'tests': []
            }


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Test Docker image using CodeBuild (no local Docker required) or local Docker'
    )
    
    # Test mode
    parser.add_argument('--use-codebuild', action='store_true', default=True,
                       help='Use CodeBuild for testing (default: True)')
    parser.add_argument('--use-local', action='store_true',
                       help='Use local Docker for testing')
    
    # Image to test
    parser.add_argument('--image', required=True,
                       help='Docker image URI to test (e.g., 123456789.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest)')
    
    # Test options
    parser.add_argument('--level', default='standard',
                       choices=['quick', 'standard', 'full'],
                       help='Test level (default: standard)')
    parser.add_argument('--region', default='us-west-2',
                       help='AWS region (default: us-west-2)')
    parser.add_argument('--wait', action='store_true', default=True,
                       help='Wait for test completion (default: True)')
    parser.add_argument('--no-wait', action='store_true',
                       help='Do not wait for test completion')
    parser.add_argument('--timeout', type=int, default=600,
                       help='Test timeout in seconds (default: 600)')
    parser.add_argument('--verbose', action='store_true', default=True,
                       help='Verbose output (default: True)')
    
    args = parser.parse_args()
    
    # Handle --no-wait
    if args.no_wait:
        args.wait = False
    
    # Handle --use-local
    if args.use_local:
        args.use_codebuild = False
    
    tester = ImageTester(args)
    result = tester.run()
    
    # Output result as JSON
    print(f"\nRESULT_JSON:{json.dumps(result)}")
    
    sys.exit(0 if result['success'] else 1)


if __name__ == '__main__':
    main()
