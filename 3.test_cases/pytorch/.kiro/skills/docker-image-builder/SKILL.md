---
name: docker-image-builder
description: Build Docker images with automatic environment detection. Uses local Docker when available, falls back to AWS CodeBuild otherwise.
license: MIT
compatibility: kiro
metadata:
  category: build
  author: opencode
  version: 2.0.0
---

## What I do

Build Docker images with **automatic environment detection**:

1. **Detect Docker**: checks if Docker is installed and running locally
2. **Local Docker** (if available): builds with conflict analysis, auto-fix, and smoke tests
3. **CodeBuild fallback** (if no Docker): uploads source to S3, triggers CodeBuild, monitors build (warns about charges)

There is a **single entry point**: `build_image.py`

## When to use me

- Build PyTorch FSDP training images
- Fix PyTorch/CUDA/torchvision compatibility issues automatically
- Build images without Docker installed locally (falls back to CodeBuild)
- Build images in a consistent, reproducible environment

## How to use me

### Single entry point (auto-detects environment)

```bash
# Auto-detect: local Docker if available, CodeBuild otherwise
python3 opencode/skills/docker-image-builder/src/build_image.py \
  --context ./FSDP

# Force local Docker
python3 opencode/skills/docker-image-builder/src/build_image.py \
  --force-local --context ./FSDP

# Force CodeBuild
python3 opencode/skills/docker-image-builder/src/build_image.py \
  --force-codebuild --codebuild-project pytorch-fsdp

# Custom image name and tag
python3 opencode/skills/docker-image-builder/src/build_image.py \
  --image-name fsdp --image-tag v1.0.0 --context ./FSDP
```

### Prerequisites

**For local Docker builds:**
- Docker installed and running

**For CodeBuild builds:**
- AWS CLI configured (`aws configure`)
- CodeBuild project created:
  ```bash
  ./opencode/skills/infrastructure/aws-cli/setup-codebuild.sh \
    --project-name pytorch-fsdp --region us-west-2
  ```

## Parameters

### Build mode (mutually exclusive, default: auto-detect)

| Parameter | Description |
|-----------|-------------|
| `--force-local` | Force local Docker (fail if not available) |
| `--force-codebuild` | Force CodeBuild (warn about charges) |

### Source options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--context` | `.` | Build context path |
| `--dockerfile` | `Dockerfile` | Path to Dockerfile (relative to context) |

### Image naming

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--image-name` | directory name | Image name |
| `--image-tag` | `latest` | Image tag |

### Auto-fix options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--auto-fix` / `--no-auto-fix` | `true` | Auto-fix conflicts |
| `--smoke-test` / `--no-smoke-test` | `true` | Run smoke tests (local only) |
| `--max-attempts` | `3` | Max rebuild attempts (local only) |
| `--base-image` | auto-detect | Override base image |

### Local Docker options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--use-sudo` | `false` | Use sudo for Docker commands |

### CodeBuild options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--codebuild-project` | `pytorch-fsdp` | CodeBuild project name |
| `--s3-bucket` | auto-generated | S3 bucket for source code |
| `--region` | `us-west-2` | AWS region |
| `--wait` / `--no-wait` | `true` | Wait for completion |
| `--timeout` | `3600` | Build timeout (seconds) |

### Output options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--verbose` / `--quiet` | `true` | Verbose output |

## Output

Returns JSON with:

```json
{
  "success": true,
  "image_name": "fsdp:latest",
  "mode": "local",
  "build_time": "45.2s",
  "attempts": 1,
  "fixes_applied": [],
  "build_id": "pytorch-fsdp:abc123"
}
```

## Auto-detection logic

```
1. --force-local?     -> Use local Docker (fail if unavailable)
2. --force-codebuild? -> Use CodeBuild (warn about charges)
3. Docker available?  -> Use local Docker
4. AWS CLI available? -> Use CodeBuild (WARN about charges)
5. Neither?           -> Error: install Docker or configure AWS CLI
```

## Conflict analysis

The builder automatically detects and fixes:

- **PyTorch/CUDA mismatches**: e.g., PyTorch 2.7 with CUDA 11.8
- **torch/torchvision conflicts**: e.g., torch==2.7.1 with torchvision==0.15.0
- **Missing --no-cache-dir**: warns about increased image size

## Examples

### Example 1: Auto-detect build

```bash
python3 opencode/skills/docker-image-builder/src/build_image.py
```

If Docker is running locally, builds locally with auto-fix. Otherwise falls back to CodeBuild.

### Example 2: CI/CD pipeline (always CodeBuild)

```bash
python3 opencode/skills/docker-image-builder/src/build_image.py \
  --force-codebuild \
  --codebuild-project pytorch-fsdp \
  --image-tag $(git rev-parse --short HEAD)
```

### Example 3: Quick local build

```bash
python3 opencode/skills/docker-image-builder/src/build_image.py \
  --force-local \
  --no-smoke-test \
  --context ./FSDP
```

### Example 4: Background CodeBuild

```bash
python3 opencode/skills/docker-image-builder/src/build_image.py \
  --force-codebuild --no-wait

# Monitor later:
aws codebuild batch-get-builds --ids pytorch-fsdp:<build-id>
```

## Typical workflow

```bash
# 1. Build image
python3 opencode/skills/docker-image-builder/src/build_image.py \
  --context ./FSDP --image-name fsdp

# 2. Push to ECR
python3 opencode/skills/ecr-image-pusher/src/push_image.py \
  --image fsdp:latest --repository fsdp

# 3. Deploy training job
python3 opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster --num_nodes 4
```

## Troubleshooting

### "Docker not available locally. Falling back to CodeBuild."

This is expected when Docker is not installed. The build will proceed via CodeBuild. Use `--force-local` if you want to fail instead.

### "CodeBuild project not found"

Create the project:
```bash
./opencode/skills/infrastructure/aws-cli/setup-codebuild.sh \
  --project-name pytorch-fsdp --region us-west-2
```

### "Neither Docker nor AWS CLI/credentials are available"

Install Docker for local builds, or configure AWS CLI for CodeBuild:
```bash
# Option A: Install Docker
# Option B: Configure AWS
aws configure
```

## Cost

- **Local Docker**: Free (uses your machine)
- **CodeBuild**: ~$0.10/build (BUILD_GENERAL1_MEDIUM, ~20-25 min for PyTorch images)
