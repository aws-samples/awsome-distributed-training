# Docker Image Builder Skill

Intelligently builds Docker images with automatic conflict detection and resolution for PyTorch/CUDA compatibility.

## Features

- 🔍 **Automatic Conflict Detection**: Analyzes Dockerfile and requirements.txt for compatibility issues
- 🔧 **Auto-Fix**: Automatically resolves PyTorch/CUDA version mismatches
- 🔄 **Smart Rebuild**: Retries with fixes on build failure (up to 3 attempts)
- 📊 **Status Updates**: Real-time progress and detailed logging
- 🎯 **Base Image Selection**: Intelligent selection of compatible base images

## Usage

### Command Line

```bash
# Basic usage - auto-detect and build
python src/build_image.py

# Build with specific Dockerfile
python src/build_image.py --dockerfile ./docker/Dockerfile.gpu

# Build with custom tag
python src/build_image.py --tag myapp:v1.0

# Disable auto-fix
python src/build_image.py --auto_fix=false

# Use sudo for Docker
python src/build_image.py --use_sudo=true
```

### As a Skill

```bash
# Trigger via opencode
/build-docker-image

# With options
/build-docker-image --dockerfile Dockerfile --tag myimage:latest --verbose
```

## Detected Issues & Fixes

### PyTorch/CUDA Mismatches
- **Detection**: Compares PyTorch version with CUDA version in base image
- **Fix**: Replaces with compatible base image (e.g., PyTorch 2.5 → CUDA 12.4)

### Torch/Torchvision Incompatibility
- **Detection**: Checks torch and torchvision version compatibility
- **Fix**: Removes torchvision if incompatible, or updates to compatible version

### Missing Optimization Flags
- **Detection**: pip install without --no-cache-dir
- **Fix**: Adds optimization flags to reduce image size

## Configuration

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `dockerfile` | string | `Dockerfile` | Path to Dockerfile |
| `context` | string | `.` | Build context path |
| `tag` | string | `auto` | Image tag (auto generates from git/timestamp) |
| `auto_fix` | boolean | `true` | Enable automatic fixes |
| `max_attempts` | integer | `3` | Maximum rebuild attempts |
| `base_image` | string | `""` | Override base image |
| `verbose` | boolean | `true` | Show detailed output |
| `use_sudo` | boolean | `false` | Use sudo for Docker |

### Auto-Generated Tags

When `tag=auto`, the skill generates tags in this priority:
1. Git tag/commit: `pytorch-fsdp:v1.2.3` or `pytorch-fsdp:abc1234`
2. Timestamp: `pytorch-fsdp:20240213-143022`

## Output

The skill outputs a JSON result:

```json
{
  "success": true,
  "image_name": "pytorch-fsdp:20240213-143022",
  "build_time": "245.3s",
  "attempts": 2,
  "fixes_applied": [
    {
      "action": "replace_base_image",
      "reason": "PyTorch 2.7 requires CUDA 12.8+",
      "old": "pytorch/pytorch:2.7.0-cuda12.1-runtime",
      "new": "pytorch/pytorch:2.5.1-cuda12.4-runtime"
    }
  ]
}
```

## Architecture

```
build_image.py
├── ConflictAnalyzer
│   ├── analyze_dockerfile()
│   ├── analyze_requirements()
│   └── get_fixes()
├── DockerfilePatcher
│   ├── apply_fixes()
│   └── patch_requirements()
├── SmokeTester
│   ├── test_imports()
│   └── test_cuda_available()
└── ImageBuilder (main)
    ├── validate_prerequisites()
    ├── build_with_fixes()
    └── run()
```

## Examples

### Example 1: Simple Build
```bash
$ /build-docker-image
🔍 Analyzing Dockerfile...
✅ No conflicts detected
📦 Building image (attempt 1/3)...
✅ Build successful: pytorch-fsdp:20240213-143022
🧪 Running smoke test...
✅ Smoke test passed
🎉 Image ready
```

### Example 2: Build with Fixes
```bash
$ /build-docker-image
🔍 Analyzing Dockerfile...
⚠️  Detected conflict: torch==2.7.1 incompatible with CUDA 12.4
🔧 Auto-fixing: Updating base image
📦 Building image (attempt 1/3)...
❌ Build failed
🔧 Analyzing failure...
📦 Rebuilding image (attempt 2/3)...
✅ Build successful
🧪 Running smoke test...
✅ Smoke test passed
🎉 Image ready with fixes applied
```

## Troubleshooting

### Docker Not Running
```
❌ Docker daemon is not running
```
**Fix**: Start Docker service

### Permission Denied
```
❌ Permission denied while trying to connect to Docker daemon
```
**Fix**: Use `--use_sudo=true` or add user to docker group

### Build Failures
If auto-fix doesn't resolve the issue:
1. Check Dockerfile syntax: `docker build --no-cache .`
2. Review build logs for specific errors
3. Try manual base image selection: `--base_image pytorch/pytorch:2.5.1-cuda12.4-runtime`

## Dependencies

- Docker (daemon running)
- Python 3.8+
- Git (for auto-tagging)

## License

MIT
