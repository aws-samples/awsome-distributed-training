---
name: ecr-image-pusher
description: Push Docker images to Amazon ECR with automatic tagging, repository creation, and push verification. Supports multiple tagging strategies including semantic versioning and git-based tags.
license: MIT
compatibility: opencode
metadata:
  category: deployment
  author: opencode
---

## What I do

Automates Docker image pushing to Amazon ECR:

1. **ECR Authentication**: Automatically authenticates with ECR
2. **Repository Management**: Creates repository if it doesn't exist
3. **Smart Tagging**: Multiple tagging strategies (auto, semantic, git-sha, latest)
4. **Push Verification**: Verifies image was pushed successfully
5. **Multi-Region**: Supports pushing to different AWS regions

## When to use me

Use this skill when you need to:
- Push a Docker image to Amazon ECR
- Automatically tag images with semantic versions
- Create ECR repositories on-the-fly
- Verify image pushes
- Push to multiple regions

## How to use me

### Command Line
```bash
# Basic usage
python3 ~/.opencode/skills/ecr-image-pusher/src/push_image.py --image fsdp:latest --repository fsdp

# With auto-tagging
python3 ~/.opencode/skills/ecr-image-pusher/src/push_image.py \
  --image fsdp:latest \
  --repository fsdp \
  --region us-west-2 \
  --tags auto \
  --create_repository true
```

### Python API
```python
from ecr_image_pusher.src.push_image import ImagePusher

pusher = ImagePusher(args)
result = pusher.push()
```

## Tagging Strategies

- **auto**: Automatically choose best strategy based on context
- **semantic**: Use semantic versioning (e.g., v1.2.3)
- **git-sha**: Use git commit SHA
- **latest**: Tag as latest

## Parameters

- `image`: Docker image name to push (required)
- `repository`: ECR repository name (required)
- `region`: AWS region (default: "us-west-2")
- `tags`: Tagging strategy - auto, semantic, git-sha, or latest (default: "auto")
- `create_repository`: Create repository if it doesn't exist (default: true)
- `verify_push`: Verify image was pushed successfully (default: true)
- `verbose`: Show detailed output (default: true)

## Output

Returns a dictionary with:
- `success`: Boolean indicating push status
- `image_uri`: Full ECR image URI
- `tags`: List of tags applied
- `repository_uri`: ECR repository URI

## Examples

### Push with semantic versioning
```bash
python3 ~/.opencode/skills/ecr-image-pusher/src/push_image.py \
  --image fsdp:v1.0.0 \
  --repository fsdp \
  --tags semantic
```

### Push to different region
```bash
python3 ~/.opencode/skills/ecr-image-pusher/src/push_image.py \
  --image fsdp:latest \
  --repository fsdp \
  --region us-east-1
```
