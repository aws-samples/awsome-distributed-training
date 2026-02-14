#!/usr/bin/env python3
"""
Docker Image Builder with CodeBuild Integration
Supports both local Docker builds and CodeBuild (S3 source).
"""

import argparse
import sys
import os
import subprocess
import tempfile
import shutil
import zipfile
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


class CodeBuildManager:
    """Manages CodeBuild builds with S3 source."""
    
    def __init__(self, logger, region: str = "us-west-2"):
        self.logger = logger
        self.region = region
        self.s3_bucket = None
        self.project_name = None
    
    def check_codebuild_project(self, project_name: str) -> Tuple[bool, str]:
        """Check if CodeBuild project exists."""
        try:
            result = subprocess.run(
                ['aws', 'codebuild', 'batch-get-projects', 
                 '--names', project_name,
                 '--region', self.region,
                 '--query', 'projects[0].name',
                 '--output', 'text'],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0 and project_name in result.stdout:
                return True, f"Project '{project_name}' exists"
            else:
                return False, f"Project '{project_name}' not found"
        except Exception as e:
            return False, str(e)
    
    def create_s3_bucket(self, bucket_name: str) -> Tuple[bool, str]:
        """Create S3 bucket for source code."""
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
    
    def upload_source_to_s3(self, context_path: str, bucket_name: str, 
                           key: str = "source/source.zip") -> Tuple[bool, str]:
        """Upload source code to S3."""
        try:
            # Create temporary zip file
            temp_dir = tempfile.mkdtemp()
            zip_path = os.path.join(temp_dir, 'source.zip')
            
            self.logger.info(f"Creating source zip from: {context_path}")
            
            # Create zip excluding unnecessary files
            with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
                for root, dirs, files in os.walk(context_path):
                    # Skip unnecessary directories
                    dirs[:] = [d for d in dirs if d not in [
                        '.git', '__pycache__', '.pytest_cache', 
                        'node_modules', '.venv', 'venv'
                    ]]
                    
                    for file in files:
                        # Skip unnecessary files
                        if file.endswith(('.pyc', '.pyo', '.DS_Store')):
                            continue
                        
                        file_path = os.path.join(root, file)
                        arc_name = os.path.relpath(file_path, context_path)
                        zipf.write(file_path, arc_name)
            
            # Upload to S3
            s3_uri = f"s3://{bucket_name}/{key}"
            self.logger.info(f"Uploading to {s3_uri}")
            
            result = subprocess.run(
                ['aws', 's3', 'cp', zip_path, s3_uri,
                 '--region', self.region],
                capture_output=True,
                text=True,
                timeout=120
            )
            
            # Cleanup
            shutil.rmtree(temp_dir)
            
            if result.returncode == 0:
                return True, s3_uri
            else:
                return False, result.stderr
                
        except Exception as e:
            return False, str(e)
    
    def trigger_codebuild(self, project_name: str, source_version: str = None,
                         source_location: str = None) -> Tuple[bool, str, str]:
        """Trigger CodeBuild with S3 source."""
        try:
            cmd = [
                'aws', 'codebuild', 'start-build',
                '--project-name', project_name,
                '--region', self.region
            ]
            
            if source_location:
                cmd.extend(['--source-location-override', source_location])
            
            if source_version:
                cmd.extend(['--source-version', source_version])
            
            self.logger.info(f"Triggering CodeBuild project: {project_name}")
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                # Parse build ID
                import json
                build_info = json.loads(result.stdout)
                build_id = build_info.get('build', {}).get('id', 'unknown')
                return True, f"Build triggered: {build_id}", build_id
            else:
                return False, result.stderr, None
                
        except Exception as e:
            return False, str(e), None
    
    def wait_for_build(self, build_id: str, timeout: int = 3600) -> Tuple[bool, str]:
        """Wait for build to complete."""
        import time
        
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
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                
                if result.returncode == 0:
                    import json
                    build_status = json.loads(result.stdout)
                    status = build_status.get('status', 'UNKNOWN')
                    phase = build_status.get('phase', 'UNKNOWN')
                    
                    self.logger.info(f"Build status: {status}, Phase: {phase}")
                    
                    if status == 'SUCCEEDED':
                        return True, "Build completed successfully"
                    elif status in ['FAILED', 'STOPPED', 'TIMED_OUT']:
                        return False, f"Build {status.lower()}"
                    
                    # Still running, wait and check again
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
            # Extract log stream name from build ID
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


class ImageBuilder:
    """Main image builder supporting both local and CodeBuild."""
    
    def __init__(self, args):
        self.args = args
        self.logger = create_logger('docker-image-builder', verbose=args.verbose)
        self.reporter = StatusReporter(self.logger)
        self.codebuild = CodeBuildManager(self.logger, region=args.region)
        self.fixes_applied = []
    
    def validate_prerequisites(self) -> bool:
        """Check prerequisites based on build mode."""
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
            # Local Docker build
            if not check_docker_installed():
                self.logger.error("Docker is not installed")
                return False
            
            if not check_docker_running():
                self.logger.error("Docker daemon is not running")
                return False
            
            self.logger.success("Docker prerequisites validated")
            return True
    
    def build_with_codebuild(self) -> Dict:
        """Build image using CodeBuild with S3 source."""
        self.logger.section("CodeBuild Build")
        
        project_name = self.args.codebuild_project
        bucket_name = self.args.s3_bucket or f"{project_name}-build-artifacts"
        
        # Check if project exists
        exists, msg = self.codebuild.check_codebuild_project(project_name)
        if not exists:
            self.logger.error(f"CodeBuild project not found: {project_name}")
            self.logger.info("Please create the project first using:")
            self.logger.info(f"  ./opencode/skills/infrastructure/aws-cli/setup-codebuild.sh \\")
            self.logger.info(f"    --project-name {project_name}")
            return {
                'success': False,
                'error': msg,
                'attempts': 0,
                'fixes_applied': []
            }
        
        self.logger.success(f"Found CodeBuild project: {project_name}")
        
        # Ensure S3 bucket exists
        success, msg = self.codebuild.create_s3_bucket(bucket_name)
        if not success:
            self.logger.error(f"Failed to create S3 bucket: {msg}")
            return {
                'success': False,
                'error': msg,
                'attempts': 0,
                'fixes_applied': []
            }
        
        self.logger.success(msg)
        
        # Upload source to S3
        success, msg = self.codebuild.upload_source_to_s3(
            self.args.context,
            bucket_name,
            "source/source.zip"
        )
        
        if not success:
            self.logger.error(f"Failed to upload source: {msg}")
            return {
                'success': False,
                'error': msg,
                'attempts': 0,
                'fixes_applied': []
            }
        
        s3_uri = msg
        self.logger.success(f"Source uploaded to: {s3_uri}")
        
        # Trigger CodeBuild
        success, msg, build_id = self.codebuild.trigger_codebuild(
            project_name,
            source_location=s3_uri
        )
        
        if not success:
            self.logger.error(f"Failed to trigger build: {msg}")
            return {
                'success': False,
                'error': msg,
                'attempts': 0,
                'fixes_applied': []
            }
        
        self.logger.success(msg)
        
        # Wait for build if requested
        if self.args.wait:
            self.logger.info("Waiting for build to complete...")
            success, msg = self.codebuild.wait_for_build(
                build_id, 
                timeout=self.args.timeout
            )
            
            if not success:
                self.logger.error(f"Build failed: {msg}")
                # Get logs
                logs = self.codebuild.get_build_logs(build_id)
                self.logger.info("Build logs:")
                print(logs)
                return {
                    'success': False,
                    'error': msg,
                    'build_id': build_id,
                    'attempts': 1,
                    'fixes_applied': []
                }
            
            self.logger.success("Build completed successfully!")
            return {
                'success': True,
                'image_name': f"{project_name}:latest",
                'build_id': build_id,
                'build_time': f"{self.args.timeout}s",
                'attempts': 1,
                'fixes_applied': []
            }
        else:
            self.logger.info("Build triggered in background")
            self.logger.info(f"Monitor with: aws codebuild batch-get-builds --ids {build_id}")
            return {
                'success': True,
                'image_name': f"{project_name}:latest",
                'build_id': build_id,
                'build_time': 'N/A (background)',
                'attempts': 1,
                'fixes_applied': []
            }
    
    def run(self) -> Dict:
        """Main entry point."""
        if not self.validate_prerequisites():
            return {
                'success': False,
                'error': 'Prerequisites not met',
                'attempts': 0,
                'fixes_applied': []
            }
        
        if self.args.use_codebuild:
            return self.build_with_codebuild()
        else:
            # Local build (existing logic)
            self.logger.info("Local Docker build not implemented in this version")
            self.logger.info("Use --use-codebuild for CodeBuild builds")
            return {
                'success': False,
                'error': 'Local build not implemented',
                'attempts': 0,
                'fixes_applied': []
            }


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Build Docker image with CodeBuild (S3 source) or local Docker'
    )
    
    # Build mode
    parser.add_argument('--use-codebuild', action='store_true', default=True,
                       help='Use CodeBuild for building (default: True)')
    parser.add_argument('--use-local', action='store_true',
                       help='Use local Docker for building')
    
    # CodeBuild options
    parser.add_argument('--codebuild-project', default='pytorch-fsdp',
                       help='CodeBuild project name (default: pytorch-fsdp)')
    parser.add_argument('--s3-bucket', default=None,
                       help='S3 bucket for source code (auto-generated if not specified)')
    parser.add_argument('--region', default='us-west-2',
                       help='AWS region (default: us-west-2)')
    parser.add_argument('--wait', action='store_true', default=True,
                       help='Wait for build to complete (default: True)')
    parser.add_argument('--timeout', type=int, default=3600,
                       help='Build timeout in seconds (default: 3600)')
    
    # Source options
    parser.add_argument('--context', default='.',
                       help='Build context path (default: .)')
    parser.add_argument('--dockerfile', default='Dockerfile',
                       help='Path to Dockerfile (default: Dockerfile)')
    
    # Output options
    parser.add_argument('--verbose', action='store_true', default=True,
                       help='Verbose output (default: True)')
    
    args = parser.parse_args()
    
    # If --use-local is specified, disable CodeBuild
    if args.use_local:
        args.use_codebuild = False
    
    builder = ImageBuilder(args)
    result = builder.run()
    
    # Output result as JSON for parsing
    import json
    print(f"\nRESULT_JSON:{json.dumps(result)}")
    
    sys.exit(0 if result['success'] else 1)


if __name__ == '__main__':
    main()
