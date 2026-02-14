#!/usr/bin/env python3
"""
Claude Code Command: Build Docker Image
Builds Docker images using CodeBuild (default - no local Docker required) or local Docker.
"""

from typing import Optional
import sys
import os
import subprocess
import json

# Add shared utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'opencode', 'skills', 'shared'))

def build_docker_image(
    dockerfile: str = "Dockerfile",
    context: str = ".",
    image_name: Optional[str] = None,
    image_tag: str = "latest",
    codebuild_project: str = "pytorch-fsdp",
    region: str = "us-west-2",
    use_codebuild: bool = True,
    wait: bool = True,
    timeout: int = 3600,
    verbose: bool = True
) -> str:
    """
    Build Docker image using CodeBuild (default) or local Docker.
    
    **CodeBuild Mode (Default - Recommended):**
    - No local Docker installation required
    - Automatically uploads source to S3
    - Builds in AWS CodeBuild
    - Perfect for CI/CD and cloud workflows
    
    **Local Mode:**
    - Requires Docker installed locally
    - Builds on your machine
    - Good for rapid iteration
    
    Args:
        dockerfile: Path to Dockerfile (default: "Dockerfile")
        context: Build context path (default: ".")
        image_name: Image name (default: current directory name)
        image_tag: Image tag (default: "latest")
        codebuild_project: CodeBuild project name (default: "pytorch-fsdp")
        region: AWS region (default: "us-west-2")
        use_codebuild: Use CodeBuild instead of local Docker (default: True)
        wait: Wait for build completion (default: True)
        timeout: Build timeout in seconds (default: 3600)
        verbose: Show detailed output (default: True)
    
    Returns:
        str: Status message with image name and build results
    
    Examples:
        "Build the Docker image"
        "Build with custom name llama3-8b"
        "Build with tag v1.0.0"
        "Build without waiting"
    """
    
    # Determine image name
    if image_name is None:
        # Use current directory name
        image_name = os.path.basename(os.getcwd())
        # Clean up the name
        image_name = ''.join(c if c.isalnum() or c == '-' else '-' for c in image_name.lower())
        image_name = image_name.strip('-')
        if not image_name:
            image_name = 'docker-image'
    
    full_image_name = f"{image_name}:{image_tag}"
    
    if use_codebuild:
        # Use CodeBuild
        cmd = [
            'python3',
            os.path.join(os.path.dirname(__file__), '..', 'opencode', 'skills', 
                        'docker-image-builder', 'src', 'build_image_codebuild.py'),
            '--codebuild-project', codebuild_project,
            '--region', region,
            '--context', context,
            '--dockerfile', dockerfile,
            '--image-name', image_name,
            '--image-tag', image_tag,
            '--timeout', str(timeout)
        ]
        
        if wait:
            cmd.append('--wait')
        
        if verbose:
            cmd.append('--verbose')
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 60)
            
            # Parse RESULT_JSON from output
            output = result.stdout
            json_start = output.find('RESULT_JSON:')
            
            if json_start != -1:
                json_str = output[json_start + len('RESULT_JSON:'):].strip()
                build_result = json.loads(json_str)
                
                if build_result.get('success'):
                    built_image = build_result.get('image_name', full_image_name)
                    build_id = build_result.get('build_id', 'unknown')
                    
                    message = f"✅ Successfully built image: {built_image}\n"
                    message += f"   Build ID: {build_id}\n"
                    
                    if not wait:
                        message += f"   Build running in background\n"
                        message += f"   Monitor: aws codebuild batch-get-builds --ids {build_id}\n"
                    
                    return message
                else:
                    error = build_result.get('error', 'Unknown error')
                    return f"❌ Build failed: {error}\n\nOutput:\n{output}"
            else:
                return f"⚠️  Build completed but couldn't parse result\n\nOutput:\n{output}"
                
        except subprocess.TimeoutExpired:
            return f"❌ Build timeout after {timeout + 60} seconds"
        except Exception as e:
            return f"❌ Error running build: {str(e)}"
    
    else:
        # Local Docker build
        return "Local Docker build not implemented in this command. Use CodeBuild (default) or run the skill directly."


if __name__ == '__main__':
    # Test the command
    print(build_docker_image())
