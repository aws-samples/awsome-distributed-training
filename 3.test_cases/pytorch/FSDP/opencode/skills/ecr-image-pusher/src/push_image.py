#!/usr/bin/env python3
"""
ECR Image Pusher Skill
Securely pushes Docker images to Amazon ECR with verification.
"""

import argparse
import sys
import os
import re
import subprocess
import json
from datetime import datetime
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass

# Add shared utilities to path
sys.path.insert(0, os.path.expanduser('~/.opencode/skills/shared'))

from logger import create_logger, StatusReporter
from docker_utils import DockerClient, check_docker_installed
from aws_utils import (
    AWSClient, validate_aws_credentials, docker_login_ecr,
    discover_ecr_repositories, get_ecr_repository_uri, create_ecr_repository
)


@dataclass
class TagStrategy:
    """Represents a tagging strategy."""
    name: str
    description: str
    generator: callable


class VersionManager:
    """Manages image versioning and tagging."""
    
    def __init__(self, logger):
        self.logger = logger
    
    def get_git_info(self) -> Dict:
        """Get git repository information."""
        info = {
            'commit': '',
            'branch': '',
            'tag': '',
            'dirty': False
        }
        
        try:
            # Get commit hash
            result = subprocess.run(
                ['git', 'rev-parse', '--short', 'HEAD'],
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                info['commit'] = result.stdout.strip()
            
            # Get branch
            result = subprocess.run(
                ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                info['branch'] = result.stdout.strip()
            
            # Get tag
            result = subprocess.run(
                ['git', 'describe', '--tags', '--exact-match', 'HEAD'],
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                info['tag'] = result.stdout.strip()
            
            # Check if dirty
            result = subprocess.run(
                ['git', 'status', '--porcelain'],
                capture_output=True,
                text=True
            )
            info['dirty'] = len(result.stdout.strip()) > 0
            
        except Exception as e:
            self.logger.debug(f"Could not get git info: {e}")
        
        return info
    
    def generate_tags_auto(self, image_name: str) -> List[str]:
        """Auto-generate tags based on git info."""
        tags = []
        git_info = self.get_git_info()
        
        # Timestamp tag (always included)
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        tags.append(timestamp)
        
        # Git tag
        if git_info['tag']:
            tags.append(git_info['tag'])
            # Also add as semantic version if valid
            if re.match(r'^v?\d+\.\d+\.\d+', git_info['tag']):
                tags.append('latest')
        
        # Git commit
        if git_info['commit']:
            tags.append(git_info['commit'])
        
        # Branch name (if not main/master)
        if git_info['branch'] and git_info['branch'] not in ['main', 'master']:
            tags.append(git_info['branch'].replace('/', '-'))
        
        if not tags:
            tags.append('latest')
        
        return tags
    
    def generate_tags_semantic(self, image_name: str) -> List[str]:
        """Generate semantic version tags."""
        tags = []
        git_info = self.get_git_info()
        
        if git_info['tag']:
            tag = git_info['tag']
            # Remove 'v' prefix if present
            if tag.startswith('v'):
                tag = tag[1:]
            
            # Add full version
            tags.append(tag)
            
            # Add minor version (e.g., 1.2)
            parts = tag.split('.')
            if len(parts) >= 2:
                tags.append(f"{parts[0]}.{parts[1]}")
            
            # Add major version (e.g., 1)
            tags.append(parts[0])
            
            # Always add latest for tagged releases
            tags.append('latest')
        else:
            # No git tag, use timestamp
            timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
            tags.append(timestamp)
            tags.append('latest')
        
        return tags
    
    def generate_tags_latest(self, image_name: str) -> List[str]:
        """Generate only 'latest' tag."""
        return ['latest']
    
    def generate_tags_git_sha(self, image_name: str) -> List[str]:
        """Generate tags based on git SHA."""
        tags = []
        git_info = self.get_git_info()
        
        if git_info['commit']:
            tags.append(git_info['commit'])
            tags.append(f"sha-{git_info['commit']}")
        else:
            timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
            tags.append(timestamp)
        
        return tags
    
    def get_strategy(self, strategy_name: str) -> TagStrategy:
        """Get tagging strategy by name."""
        strategies = {
            'auto': TagStrategy('auto', 'Auto-detect from git', self.generate_tags_auto),
            'semantic': TagStrategy('semantic', 'Semantic versioning', self.generate_tags_semantic),
            'latest': TagStrategy('latest', 'Latest only', self.generate_tags_latest),
            'git-sha': TagStrategy('git-sha', 'Git SHA based', self.generate_tags_git_sha),
        }
        
        return strategies.get(strategy_name, strategies['auto'])
    
    def generate_tags(self, strategy_name: str, image_name: str) -> List[str]:
        """Generate tags using specified strategy."""
        strategy = self.get_strategy(strategy_name)
        self.logger.info(f"Using tagging strategy: {strategy.name} ({strategy.description})")
        return strategy.generator(image_name)


class ECRImagePusher:
    """Main ECR image pusher."""
    
    def __init__(self, args):
        self.args = args
        self.logger = create_logger('ecr-image-pusher', verbose=args.verbose)
        self.reporter = StatusReporter(self.logger)
        self.docker = DockerClient(use_sudo=args.use_sudo)
        self.version_manager = VersionManager(self.logger)
        self.aws = AWSClient(profile_name=args.profile, region=args.region)
        
        self.repository_uri = None
        self.pushed_tags = []
    
    def validate_prerequisites(self) -> bool:
        """Check all prerequisites."""
        self.logger.info("Validating prerequisites...")
        
        # Check Docker
        if not check_docker_installed():
            self.logger.error("Docker is not installed")
            return False
        
        # Check AWS credentials
        if not validate_aws_credentials(self.args.profile):
            self.logger.error("AWS credentials not valid")
            self.logger.info("Run: aws configure")
            return False
        
        self.logger.success("Prerequisites validated")
        return True
    
    def get_image_to_push(self) -> str:
        """Determine which image to push."""
        if self.args.image:
            return self.args.image
        
        # Try to find recently built/tested image
        self.logger.info("No image specified, looking for recent images...")
        
        # List local images
        images = self.docker.images(filter_name="pytorch-fsdp")
        if images:
            # Get most recent
            image = images[0]
            image_name = f"{image['Repository']}:{image['Tag']}"
            self.logger.info(f"Found recent image: {image_name}")
            return image_name
        
        return "pytorch-fsdp:latest"  # Default fallback
    
    def setup_ecr_repository(self) -> bool:
        """Setup ECR repository."""
        self.logger.info(f"Setting up ECR repository: {self.args.repository}")
        
        # Check if repository exists
        repo_uri = get_ecr_repository_uri(
            self.args.repository,
            self.args.region,
            self.args.profile
        )
        
        if repo_uri:
            self.logger.success(f"Repository exists: {repo_uri}")
            self.repository_uri = repo_uri
            return True
        
        # Create if allowed
        if self.args.create_repository:
            self.logger.info("Repository not found, creating...")
            if create_ecr_repository(
                self.args.repository,
                self.args.region,
                self.args.profile
            ):
                # Get URI of newly created repo
                repo_uri = get_ecr_repository_uri(
                    self.args.repository,
                    self.args.region,
                    self.args.profile
                )
                self.repository_uri = repo_uri
                return True
        else:
            self.logger.error(f"Repository does not exist: {self.args.repository}")
            self.logger.info("Use --create_repository=true to create it")
        
        return False
    
    def authenticate_with_ecr(self) -> bool:
        """Authenticate Docker with ECR."""
        self.logger.info("Authenticating with ECR...")
        
        account_id = self.aws.get_account_id()
        registry_id = account_id
        
        success = docker_login_ecr(
            registry_id,
            self.args.region,
            self.args.profile
        )
        
        if success:
            self.logger.success("Authenticated with ECR")
        else:
            self.logger.error("Failed to authenticate with ECR")
        
        return success
    
    def tag_image(self, source_image: str, tags: List[str]) -> List[str]:
        """Tag image for ECR."""
        tagged_images = []
        
        for tag in tags:
            target = f"{self.repository_uri}:{tag}"
            self.logger.info(f"Tagging: {source_image} → {target}")
            
            if self.docker.tag(source_image, target):
                tagged_images.append(target)
                self.logger.success(f"Tagged: {target}")
            else:
                self.logger.error(f"Failed to tag: {target}")
        
        return tagged_images
    
    def push_images(self, images: List[str]) -> bool:
        """Push tagged images to ECR."""
        self.logger.section("Pushing Images to ECR")
        
        all_success = True
        
        for image in images:
            self.logger.info(f"Pushing: {image}")
            
            success, output = self.docker.push(image)
            
            if success:
                self.logger.success(f"Pushed: {image}")
                self.pushed_tags.append(image.split(':')[-1])
            else:
                self.logger.error(f"Failed to push: {image}")
                self.logger.debug(output)
                all_success = False
        
        return all_success
    
    def verify_push(self) -> bool:
        """Verify images were pushed successfully."""
        if not self.args.verify_push:
            return True
        
        self.logger.info("Verifying push...")
        
        try:
            ecr = self.aws.get_ecr_client()
            
            for tag in self.pushed_tags:
                response = ecr.describe_images(
                    repositoryName=self.args.repository,
                    imageIds=[{'imageTag': tag}]
                )
                
                if response['imageDetails']:
                    image = response['imageDetails'][0]
                    self.logger.success(
                        f"Verified: {tag} (digest: {image['imageDigest'][:19]}...)"
                    )
                else:
                    self.logger.error(f"Not found in ECR: {tag}")
                    return False
            
            return True
            
        except Exception as e:
            self.logger.error(f"Verification failed: {e}")
            return False
    
    def run(self) -> Dict:
        """Main push workflow."""
        start_time = datetime.now()
        
        self.logger.section("ECR Image Pusher")
        self.logger.info(f"Repository: {self.args.repository}")
        self.logger.info(f"Region: {self.args.region}")
        self.logger.info(f"Tag strategy: {self.args.tags}")
        
        # Validate prerequisites
        if not self.validate_prerequisites():
            return {'success': False, 'error': 'Prerequisites not met'}
        
        # Get image to push
        source_image = self.get_image_to_push()
        self.logger.info(f"Source image: {source_image}")
        
        # Setup ECR repository
        if not self.setup_ecr_repository():
            return {'success': False, 'error': 'Failed to setup ECR repository'}
        
        # Authenticate
        if not self.authenticate_with_ecr():
            return {'success': False, 'error': 'Failed to authenticate with ECR'}
        
        # Generate tags
        tags = self.version_manager.generate_tags(self.args.tags, source_image)
        self.logger.info(f"Tags to apply: {', '.join(tags)}")
        
        # Tag images
        tagged_images = self.tag_image(source_image, tags)
        if not tagged_images:
            return {'success': False, 'error': 'Failed to tag images'}
        
        # Push images
        if not self.push_images(tagged_images):
            return {'success': False, 'error': 'Failed to push some images'}
        
        # Verify
        if not self.verify_push():
            return {'success': False, 'error': 'Push verification failed'}
        
        # Calculate time
        push_time = (datetime.now() - start_time).total_seconds()
        
        # Summary
        self.logger.section("Push Summary")
        self.logger.success(f"Repository: {self.repository_uri}")
        self.logger.info(f"Tags pushed: {', '.join(self.pushed_tags)}")
        self.logger.info(f"Push time: {push_time:.1f}s")
        
        return {
            'success': True,
            'repository_uri': self.repository_uri,
            'tags_pushed': self.pushed_tags,
            'push_time': f"{push_time:.1f}s",
            'region': self.args.region
        }


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Push Docker image to ECR')
    parser.add_argument('--image', default='', help='Image to push')
    parser.add_argument('--repository', default='fsdp', help='ECR repository name')
    parser.add_argument('--region', default='us-west-2', help='AWS region')
    parser.add_argument('--profile', default='', help='AWS profile')
    parser.add_argument('--tags', default='auto', 
                       choices=['auto', 'semantic', 'latest', 'git-sha'],
                       help='Tagging strategy')
    parser.add_argument('--create_repository', type=lambda x: x.lower() == 'true',
                       default=True, help='Create repository if not exists')
    parser.add_argument('--verify_push', type=lambda x: x.lower() == 'true',
                       default=True, help='Verify push')
    parser.add_argument('--verbose', type=lambda x: x.lower() == 'true',
                       default=True, help='Verbose output')
    parser.add_argument('--use_sudo', type=lambda x: x.lower() == 'true',
                       default=False, help='Use sudo')
    
    args = parser.parse_args()
    
    pusher = ECRImagePusher(args)
    result = pusher.run()
    
    # Output result
    print(f"\nRESULT_JSON:{json.dumps(result)}")
    
    sys.exit(0 if result['success'] else 1)


if __name__ == '__main__':
    main()
