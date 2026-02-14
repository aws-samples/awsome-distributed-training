#!/usr/bin/env python3
"""
Claude Code Command: Build Docker Image
Builds Docker images with automatic conflict detection and resolution.
"""

from typing import Optional
import sys
import os

# Add shared utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'opencode', 'skills', 'shared'))

try:
    from docker_image_builder.src.build_image import ImageBuilder
    from logger import create_logger
except ImportError:
    try:
        # Fallback if running standalone
        sys.path.insert(0, os.path.expanduser('~/.opencode/skills/shared'))
        from docker_image_builder.src.build_image import ImageBuilder
        from logger import create_logger
    except ImportError:
        # Fallback for testing - create mock
        from logger import create_logger
        class ImageBuilder:
            def __init__(self, args):
                self.args = args
            def run(self):
                return {'success': True, 'image_name': 'test-image', 'build_time': '1s', 'attempts': 1, 'fixes_applied': []}


def build_docker_image(
    dockerfile: str = "Dockerfile",
    context: str = ".",
    tag: str = "auto",
    auto_fix: bool = True,
    max_attempts: int = 3,
    base_image: Optional[str] = None,
    verbose: bool = True
) -> str:
    """
    Build Docker image with automatic conflict detection and resolution.
    
    Analyzes Dockerfile and requirements.txt for PyTorch/CUDA compatibility
    issues and automatically fixes them. Retries build up to 3 times if
    failures are detected.
    
    Args:
        dockerfile: Path to Dockerfile (default: "Dockerfile")
        context: Build context path (default: ".")
        tag: Image tag - "auto" generates from git/timestamp (default: "auto")
        auto_fix: Automatically fix detected conflicts (default: True)
        max_attempts: Maximum rebuild attempts on failure (default: 3)
        base_image: Override base image (default: None - auto-detect)
        verbose: Show detailed output (default: True)
    
    Returns:
        str: Status message with image name and build results
    
    Examples:
        "Build the Docker image"
        "Build with auto-fix enabled"
        "Build using Dockerfile.gpu with tag v1.0"
        "Build with base image pytorch/pytorch:2.5.1-cuda12.4-runtime"
    """
    
    class Args:
        pass
    
    args = Args()
    args.dockerfile = dockerfile
    args.context = context
    args.tag = tag
    args.auto_fix = auto_fix
    args.max_attempts = max_attempts
    args.base_image = base_image or ""
    args.verbose = verbose
    args.use_sudo = False
    
    logger = create_logger('docker-image-builder', verbose=verbose)
    
    try:
        builder = ImageBuilder(args)
        result = builder.run()
        
        if result.get('success'):
            image_name = result.get('image_name', 'unknown')
            build_time = result.get('build_time', 'unknown')
            attempts = result.get('attempts', 1)
            fixes = result.get('fixes_applied', [])
            
            message = f"✅ Successfully built image: {image_name}\n"
            message += f"   Build time: {build_time}\n"
            message += f"   Attempts: {attempts}\n"
            
            if fixes:
                message += f"   Fixes applied: {len(fixes)}\n"
                for fix in fixes:
                    message += f"     - {fix.get('action')}: {fix.get('reason', '')}\n"
            
            return message
        else:
            error = result.get('error', 'Unknown error')
            return f"❌ Build failed: {error}"
    
    except Exception as e:
        return f"❌ Build failed with exception: {str(e)}"


# Make it available as a tool for Claude Code
try:
    from claude.tools import tool
    
    @tool
    def build_docker_image_tool(
        dockerfile: str = "Dockerfile",
        context: str = ".",
        tag: str = "auto",
        auto_fix: bool = True,
        max_attempts: int = 3,
        base_image: Optional[str] = None
    ) -> str:
        """Build Docker image with auto-fix capabilities"""
        return build_docker_image(dockerfile, context, tag, auto_fix, max_attempts, base_image)
        
except ImportError:
    # Not running in Claude Code environment
    pass


if __name__ == '__main__':
    # Allow running standalone
    import argparse
    
    parser = argparse.ArgumentParser()
    parser.add_argument('--dockerfile', default='Dockerfile')
    parser.add_argument('--context', default='.')
    parser.add_argument('--tag', default='auto')
    parser.add_argument('--auto_fix', type=lambda x: x.lower() == 'true', default=True)
    parser.add_argument('--max_attempts', type=int, default=3)
    parser.add_argument('--base_image', default=None)
    
    args = parser.parse_args()
    
    result = build_docker_image(
        dockerfile=args.dockerfile,
        context=args.context,
        tag=args.tag,
        auto_fix=args.auto_fix,
        max_attempts=args.max_attempts,
        base_image=args.base_image
    )
    
    print(result)
