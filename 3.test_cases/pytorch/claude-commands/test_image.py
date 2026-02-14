#!/usr/bin/env python3
"""
Claude Code Command: Test Docker Image
Test Docker images using CodeBuild (default - no local Docker required) or local Docker.
"""

from typing import Optional
import sys
import os
import subprocess
import json

def test_docker_image(
    image: str,
    level: str = "standard",
    codebuild_project: str = "pytorch-fsdp",
    region: str = "us-west-2",
    use_codebuild: bool = True,
    wait: bool = True,
    timeout: int = 600,
    verbose: bool = True
) -> str:
    """
    Test Docker image using CodeBuild (default) or local Docker.
    
    **CodeBuild Mode (Default - Recommended):**
    - No local Docker installation required
    - Tests run entirely in AWS CodeBuild
    - Perfect for CI/CD and cloud workflows
    
    **Test Levels:**
    - quick: Basic imports only (~2-3 minutes)
    - standard: Imports + CUDA + model config (~5-7 minutes)
    - full: All tests including model loading (~10-15 minutes)
    
    Args:
        image: Docker image URI to test (required)
               Format: ACCOUNT.dkr.ecr.REGION.amazonaws.com/REPOSITORY:TAG
        level: Test level - quick, standard, or full (default: "standard")
        codebuild_project: CodeBuild project name (default: "pytorch-fsdp")
        region: AWS region (default: "us-west-2")
        use_codebuild: Use CodeBuild instead of local Docker (default: True)
        wait: Wait for test completion (default: True)
        timeout: Test timeout in seconds (default: 600)
        verbose: Show detailed output (default: True)
    
    Returns:
        str: Status message with test results
    
    Examples:
        "Test the Docker image"
        "Test with level quick"
        "Test the fsdp:latest image"
        "Run full tests on the image"
    """
    
    if use_codebuild:
        # Use CodeBuild
        cmd = [
            'python3',
            os.path.join(os.path.dirname(__file__), '..', 'opencode', 'skills', 
                        'docker-image-tester', 'src', 'test_image_codebuild.py'),
            '--image', image,
            '--level', level,
            '--region', region,
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
                test_result = json.loads(json_str)
                
                if test_result.get('success'):
                    tested_image = test_result.get('image', image)
                    build_id = test_result.get('build_id', 'unknown')
                    message = test_result.get('message', 'Tests completed')
                    
                    msg = f"✅ Tests passed for image: {tested_image}\n"
                    msg += f"   Test Level: {level}\n"
                    msg += f"   Build ID: {build_id}\n"
                    msg += f"   Message: {message}\n"
                    
                    if not wait:
                        msg += f"   Tests running in background\n"
                        msg += f"   Monitor: aws codebuild batch-get-builds --ids {build_id}\n"
                    
                    return msg
                else:
                    error = test_result.get('error', 'Unknown error')
                    return f"❌ Tests failed: {error}\n\nOutput:\n{output}"
            else:
                return f"⚠️  Tests completed but couldn't parse result\n\nOutput:\n{output}"
                
        except subprocess.TimeoutExpired:
            return f"❌ Test timeout after {timeout + 60} seconds"
        except Exception as e:
            return f"❌ Error running tests: {str(e)}"
    
    else:
        # Local Docker test
        return "Local Docker testing not implemented in this command. Use CodeBuild (default) or run the skill directly."


if __name__ == '__main__':
    # Test the command
    print(test_docker_image(image="fsdp:latest"))
