#!/usr/bin/env python3
"""
Claude Code Command: Build Docker Image
Builds Docker images with automatic environment detection.
If Docker is available locally, builds locally with conflict analysis + auto-fix.
If Docker is NOT available, falls back to AWS CodeBuild (warns about charges).
"""

from typing import Optional
import sys
import os
import subprocess
import json


def build_docker_image(
    dockerfile: str = "Dockerfile",
    context: str = ".",
    image_name: Optional[str] = None,
    image_tag: str = "latest",
    force_local: bool = False,
    force_codebuild: bool = False,
    codebuild_project: str = "pytorch-fsdp",
    region: str = "us-west-2",
    auto_fix: bool = True,
    smoke_test: bool = True,
    wait: bool = True,
    timeout: int = 3600,
    verbose: bool = True
) -> str:
    """
    Build Docker image with automatic environment detection.

    Auto-detection logic:
    1. If Docker is available locally -> builds locally with conflict analysis, auto-fix, smoke tests
    2. If Docker is NOT available -> falls back to CodeBuild (warns about ~$0.10/build charges)

    Use force_local=True or force_codebuild=True to override auto-detection.

    Args:
        dockerfile: Path to Dockerfile (default: "Dockerfile")
        context: Build context path (default: ".")
        image_name: Image name (default: current directory name)
        image_tag: Image tag (default: "latest")
        force_local: Force local Docker build (default: False)
        force_codebuild: Force CodeBuild build (default: False)
        codebuild_project: CodeBuild project name (default: "pytorch-fsdp")
        region: AWS region (default: "us-west-2")
        auto_fix: Auto-fix detected conflicts (default: True)
        smoke_test: Run smoke tests after local build (default: True)
        wait: Wait for build completion (default: True)
        timeout: Build timeout in seconds (default: 3600)
        verbose: Show detailed output (default: True)

    Returns:
        str: Status message with image name and build results

    Examples:
        "Build the Docker image"
        "Build with local Docker"
        "Build with CodeBuild"
        "Build with custom name llama3-8b"
        "Build with tag v1.0.0"
    """

    # Determine image name
    if image_name is None:
        image_name = os.path.basename(os.getcwd())
        image_name = ''.join(c if c.isalnum() or c == '-' else '-' for c in image_name.lower())
        image_name = image_name.strip('-')
        if not image_name:
            image_name = 'docker-image'

    full_image_name = f"{image_name}:{image_tag}"

    # Build command using unified build_image.py
    skill_script = os.path.join(
        os.path.dirname(__file__), '..', 'opencode', 'skills',
        'docker-image-builder', 'src', 'build_image.py'
    )

    cmd = [
        'python3', skill_script,
        '--context', context,
        '--dockerfile', dockerfile,
        '--image-name', image_name,
        '--image-tag', image_tag,
        '--codebuild-project', codebuild_project,
        '--region', region,
        '--timeout', str(timeout),
        '--max-attempts', '3'
    ]

    # Build mode
    if force_local:
        cmd.append('--force-local')
    elif force_codebuild:
        cmd.append('--force-codebuild')
    # Otherwise: auto-detect (default)

    # Options
    if auto_fix:
        cmd.append('--auto-fix')
    else:
        cmd.append('--no-auto-fix')

    if smoke_test:
        cmd.append('--smoke-test')
    else:
        cmd.append('--no-smoke-test')

    if wait:
        pass  # --wait is the default
    else:
        cmd.append('--no-wait')

    if verbose:
        cmd.append('--verbose')
    else:
        cmd.append('--quiet')

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 120)

        # Parse RESULT_JSON from output
        output = result.stdout
        json_start = output.find('RESULT_JSON:')

        if json_start != -1:
            json_str = output[json_start + len('RESULT_JSON:'):].strip()
            build_result = json.loads(json_str)

            if build_result.get('success'):
                built_image = build_result.get('image_name', full_image_name)
                mode = build_result.get('mode', 'unknown')
                build_time = build_result.get('build_time', 'N/A')
                build_id = build_result.get('build_id', '')
                fixes = build_result.get('fixes_applied', [])

                message = f"Successfully built image: {built_image}\n"
                message += f"   Mode: {mode}\n"
                message += f"   Build time: {build_time}\n"

                if build_id:
                    message += f"   Build ID: {build_id}\n"

                if fixes:
                    message += f"   Fixes applied: {len(fixes)}\n"
                    for fix in fixes:
                        message += f"     - {fix.get('action', 'fix')}: {fix.get('reason', '')}\n"

                if not wait and mode == 'codebuild':
                    message += f"   Build running in background\n"
                    message += f"   Monitor: aws codebuild batch-get-builds --ids {build_id}\n"

                return message
            else:
                error = build_result.get('error', 'Unknown error')
                mode = build_result.get('mode', 'unknown')
                return f"Build failed ({mode} mode): {error}\n\nFull output:\n{output}"
        else:
            if result.returncode == 0:
                return f"Build completed but couldn't parse result\n\nOutput:\n{output}"
            else:
                return f"Build failed (exit code {result.returncode})\n\nStdout:\n{output}\n\nStderr:\n{result.stderr}"

    except subprocess.TimeoutExpired:
        return f"Build timeout after {timeout + 120} seconds"
    except Exception as e:
        return f"Error running build: {str(e)}"


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(
        description='Build Docker image with auto-detection (local Docker or CodeBuild)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Auto-detect (local Docker preferred, CodeBuild fallback)
  python build_image.py --context ./FSDP

  # Force local Docker
  python build_image.py --force-local --context ./FSDP

  # Force CodeBuild
  python build_image.py --force-codebuild --codebuild-project pytorch-fsdp

  # Custom image name and tag
  python build_image.py --image-name fsdp --image-tag v1.0.0
        """
    )

    parser.add_argument('--dockerfile', default='Dockerfile', help='Path to Dockerfile')
    parser.add_argument('--context', default='.', help='Build context path')
    parser.add_argument('--image-name', default=None, help='Image name')
    parser.add_argument('--image-tag', default='latest', help='Image tag')
    parser.add_argument('--force-local', action='store_true', help='Force local Docker build')
    parser.add_argument('--force-codebuild', action='store_true', help='Force CodeBuild build')
    parser.add_argument('--codebuild-project', default='pytorch-fsdp', help='CodeBuild project name')
    parser.add_argument('--region', default='us-west-2', help='AWS region')
    parser.add_argument('--no-auto-fix', dest='auto_fix', action='store_false', default=True, help='Disable auto-fix')
    parser.add_argument('--no-smoke-test', dest='smoke_test', action='store_false', default=True, help='Skip smoke tests')
    parser.add_argument('--no-wait', dest='wait', action='store_false', default=True, help='Do not wait for completion')
    parser.add_argument('--timeout', type=int, default=3600, help='Build timeout')

    args = parser.parse_args()

    print(build_docker_image(
        dockerfile=args.dockerfile,
        context=args.context,
        image_name=args.image_name,
        image_tag=args.image_tag,
        force_local=args.force_local,
        force_codebuild=args.force_codebuild,
        codebuild_project=args.codebuild_project,
        region=args.region,
        auto_fix=args.auto_fix,
        smoke_test=args.smoke_test,
        wait=args.wait,
        timeout=args.timeout
    ))
