---
name: docker-image-builder
description: Build Docker images with automatic conflict detection and resolution. Analyzes Dockerfiles and requirements.txt for PyTorch/CUDA compatibility issues, auto-fixes conflicts, and rebuilds on failure.
license: MIT
compatibility: opencode
metadata:
  category: build
  author: opencode
---

## What I do

Intelligently builds Docker images with the following capabilities:

1. **Conflict Detection**: Analyzes Dockerfile and requirements.txt for:
   - PyTorch/CUDA version mismatches
   - Incompatible package versions
   - Missing dependencies

2. **Auto-Fix**: Automatically resolves issues by:
   - Selecting compatible base images
   - Removing conflicting packages
   - Updating version specifications

3. **Retry Logic**: Rebuilds up to 3 times with progressive fixes

4. **Smart Tagging**: Generates tags from git info or timestamps

## When to use me

Use this skill when you need to:
- Build a Docker image for PyTorch FSDP training
- Fix PyTorch/CUDA compatibility issues
- Automatically resolve dependency conflicts
- Build images with proper versioning

## How to use me

### Command Line
```bash
# Basic usage
python3 ~/.opencode/skills/docker-image-builder/src/build_image.py

# With options
python3 ~/.opencode/skills/docker-image-builder/src/build_image.py \
  --dockerfile Dockerfile \
  --context . \
  --tag auto \
  --auto_fix true \
  --max_attempts 3
```

### Python API
```python
from docker_image_builder.src.build_image import ImageBuilder

builder = ImageBuilder(args)
result = builder.run()
```

## Parameters

- `dockerfile`: Path to Dockerfile (default: "Dockerfile")
- `context`: Build context path (default: ".")
- `tag`: Image tag - "auto" generates from git/timestamp (default: "auto")
- `auto_fix`: Automatically fix detected conflicts (default: true)
- `max_attempts`: Maximum rebuild attempts on failure (default: 3)
- `base_image`: Override base image (default: auto-detect)
- `verbose`: Show detailed status updates (default: true)

## Output

Returns a dictionary with:
- `success`: Boolean indicating build status
- `image_name`: Name of the built image
- `build_time`: Duration in seconds
- `attempts`: Number of build attempts
- `fixes_applied`: List of fixes applied

## Examples

### Build with auto-fix
```bash
python3 ~/.opencode/skills/docker-image-builder/src/build_image.py --auto_fix true
```

### Build with custom tag
```bash
python3 ~/.opencode/skills/docker-image-builder/src/build_image.py --tag v1.0.0
```

### Build specific Dockerfile
```bash
python3 ~/.opencode/skills/docker-image-builder/src/build_image.py --dockerfile Dockerfile.gpu
```
