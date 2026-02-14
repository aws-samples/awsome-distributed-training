---
name: docker-image-builder
description: Build Docker images using AWS CodeBuild with S3 source (default) or local Docker. Automatically uploads source to S3, triggers CodeBuild, and monitors the build process. No local Docker required!
license: MIT
compatibility: opencode
metadata:
  category: build
  author: opencode
  default_mode: codebuild
---

## What I do

Build Docker images using **AWS CodeBuild with S3 source** (default) or local Docker:

### CodeBuild Mode (Default - Recommended)
1. **Upload Source**: Automatically zips and uploads your source code to S3
2. **Trigger CodeBuild**: Starts a build using the uploaded S3 source
3. **Monitor Progress**: Optionally waits for build completion and streams logs
4. **No Local Docker Required**: Everything runs in AWS CodeBuild

### Local Mode (Optional)
1. **Conflict Detection**: Analyzes Dockerfile and requirements.txt
2. **Auto-Fix**: Resolves PyTorch/CUDA compatibility issues
3. **Local Build**: Builds image using local Docker daemon

## When to use me

Use this skill when you need to:
- **Build a Docker image without installing Docker locally** (use CodeBuild mode)
- Build PyTorch FSDP training images
- Fix PyTorch/CUDA compatibility issues
- Build images in a consistent, reproducible environment
- Scale builds without local resource constraints

## How to use me

### CodeBuild Mode (Default)

```bash
# Basic usage - uploads source to S3 and triggers CodeBuild
python3 opencode/skills/docker-image-builder/src/build_image_codebuild.py

# With custom project name
python3 opencode/skills/docker-image-builder/src/build_image_codebuild.py \
  --codebuild-project my-project \
  --region us-west-2

# Specify custom S3 bucket (auto-created if doesn't exist)
python3 opencode/skills/docker-image-builder/src/build_image_codebuild.py \
  --s3-bucket my-custom-bucket

# Don't wait for build completion (background mode)
python3 opencode/skills/docker-image-builder/src/build_image_codebuild.py \
  --no-wait
```

### Prerequisites for CodeBuild Mode

1. **AWS CLI configured**:
   ```bash
   aws configure
   # Set AWS Access Key ID, Secret Access Key, region (us-west-2)
   ```

2. **CodeBuild project exists** (create if needed):
   ```bash
   # Using the setup script
   ./opencode/skills/infrastructure/aws-cli/setup-codebuild.sh \
     --project-name pytorch-fsdp \
     --region us-west-2
   
   # Or manually via AWS Console
   ```

### Local Mode (Requires Docker)

```bash
# Force local build (requires Docker installed)
python3 opencode/skills/docker-image-builder/src/build_image.py \
  --use-local \
  --dockerfile Dockerfile \
  --auto_fix true
```

## Parameters

### CodeBuild Mode Parameters

- `--use-codebuild`: Use CodeBuild (default: True)
- `--codebuild-project`: CodeBuild project name (default: "pytorch-fsdp")
- `--s3-bucket`: S3 bucket for source code (default: auto-generated as `{project-name}-build-artifacts`)
- `--region`: AWS region (default: "us-west-2")
- `--wait`: Wait for build completion (default: True)
- `--no-wait`: Don't wait, run in background
- `--timeout`: Build timeout in seconds (default: 3600)
- `--context`: Build context path (default: ".")
- `--dockerfile`: Path to Dockerfile (default: "Dockerfile")
- `--image-name`: Image name (default: current directory name, e.g., "my-project")
- `--image-tag`: Image tag (default: "latest")
- `--verbose`: Show detailed output (default: True)

**Image Naming:**
- By default, the image name is derived from the current directory name
- Example: If you're in `/home/user/my-training-project`, image will be named `my-training-project:latest`
- Use `--image-name` to override with a custom name
- Use `--image-tag` to specify a custom tag (e.g., `v1.0.0`, `2024-01-15`)

### Local Mode Parameters

- `--use-local`: Use local Docker instead of CodeBuild
- `--dockerfile`: Path to Dockerfile (default: "Dockerfile")
- `--context`: Build context path (default: ".")
- `--tag`: Image tag - "auto" generates from git/timestamp (default: "auto")
- `--auto_fix`: Automatically fix detected conflicts (default: true)
- `--max_attempts`: Maximum rebuild attempts on failure (default: 3)
- `--base_image`: Override base image (default: auto-detect)
- `--verbose`: Show detailed status updates (default: true)

## Output

Returns a dictionary with:
- `success`: Boolean indicating build status
- `image_name`: Name of the built image (e.g., "pytorch-fsdp:latest")
- `build_id`: CodeBuild build ID (for monitoring)
- `build_time`: Duration in seconds
- `attempts`: Number of build attempts
- `fixes_applied`: List of fixes applied (local mode only)

## Examples

### Example 1: Quick CodeBuild Build

```bash
# Simplest usage - uses default project 'pytorch-fsdp'
python3 opencode/skills/docker-image-builder/src/build_image_codebuild.py
```

**What happens:**
1. Creates S3 bucket `pytorch-fsdp-build-artifacts` (if needed)
2. Uploads current directory to S3
3. Triggers CodeBuild project 'pytorch-fsdp'
4. Waits for completion and shows logs

### Example 2: Custom Project

```bash
python3 opencode/skills/docker-image-builder/src/build_image_codebuild.py \
  --codebuild-project my-training-project \
  --s3-bucket my-training-bucket \
  --region us-east-1
```

### Example 3: Custom Image Name

```bash
# Build with custom image name (instead of using directory name)
python3 opencode/skills/docker-image-builder/src/build_image_codebuild.py \
  --image-name llama3-8b-training \
  --image-tag v1.0.0

# Build with timestamp tag
python3 opencode/skills/docker-image-builder/src/build_image_codebuild.py \
  --image-tag $(date +%Y%m%d-%H%M%S)
```

### Example 4: Background Build

```bash
# Start build without waiting
python3 opencode/skills/docker-image-builder/src/build_image_codebuild.py \
  --no-wait

# Later, check build status:
aws codebuild batch-get-builds \
  --ids pytorch-fsdp:<build-id-from-output> \
  --region us-west-2
```

### Example 5: Local Build (Requires Docker)

```bash
# Only if you have Docker installed locally
python3 opencode/skills/docker-image-builder/src/build_image.py \
  --use-local \
  --dockerfile Dockerfile \
  --auto_fix true \
  --max_attempts 3
```

## Workflow

### Typical CodeBuild Workflow

```bash
# 1. Build image using CodeBuild
python3 opencode/skills/docker-image-builder/src/build_image_codebuild.py \
  --codebuild-project pytorch-fsdp

# 2. Check the built image in ECR
aws ecr describe-images \
  --repository-name fsdp \
  --region us-west-2

# 3. Deploy training job using the new image
python3 opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster \
  --num_nodes 4
```

## Troubleshooting

### "CodeBuild project not found"

Create the project first:
```bash
./opencode/skills/infrastructure/aws-cli/setup-codebuild.sh \
  --project-name pytorch-fsdp \
  --region us-west-2
```

### "AWS credentials not configured"

Configure AWS CLI:
```bash
aws configure
```

### "Build failed"

Check CloudWatch logs:
```bash
aws logs tail /aws/codebuild/pytorch-fsdp --follow
```

### "S3 permission denied"

Ensure your AWS user/role has these permissions:
- `s3:CreateBucket`
- `s3:PutObject`
- `s3:GetObject`
- `codebuild:StartBuild`
- `codebuild:BatchGetBuilds`
- `logs:GetLogEvents`

## Why CodeBuild?

**Advantages over local Docker builds:**
- ✅ No need to install Docker locally
- ✅ Consistent build environment
- ✅ Scalable (can run multiple builds in parallel)
- ✅ Integrated with AWS ecosystem
- ✅ Build history and logs in CloudWatch
- ✅ Cost-effective (pay per minute)

**Build Time:**
- PyTorch/CUDA images: ~20-25 minutes (typical)
- Standard images: ~5-10 minutes

**Cost:**
- ~$0.10 per build (BUILD_GENERAL1_MEDIUM at $0.012/minute)
