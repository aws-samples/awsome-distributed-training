# Opencode Skills for PyTorch FSDP

This directory contains project-specific skill configurations and overrides for the PyTorch FSDP Docker image building workflow.

## Overview

These skills provide autonomous Docker image building, testing, and ECR pushing capabilities:

1. **docker-image-builder** - Intelligently builds images with auto-fix
2. **docker-image-tester** - Comprehensive testing with recommendations  
3. **ecr-image-pusher** - Secure ECR authentication and pushing

## Quick Start

### Using the Skills

```bash
# Build Docker image with auto-fix
opencode /build-docker-image

# Test the image
opencode /test-docker-image

# Push to ECR
opencode /push-to-ecr
```

### Full Workflow

```bash
# Complete build-test-push workflow
opencode /build-docker-image && \
opencode /test-docker-image && \
opencode /push-to-ecr
```

## Configuration

### Global vs Project Skills

- **Global**: `~/.opencode/skills/` - Available in all projects
- **Project**: `.opencode/skills/` - Project-specific overrides

This project uses both:
- Global skills provide base functionality
- Project-specific configurations customize behavior

### Environment Variables

Create `.env` file:

```bash
# AWS Configuration
AWS_PROFILE=default
AWS_REGION=us-west-2
ECR_REPOSITORY=fsdp

# Build Configuration
BUILD_TIMEOUT=60
TEST_LEVEL=standard
TAG_STRATEGY=auto
```

## Skill Details

### 1. Docker Image Builder

**Purpose**: Build Docker images with automatic conflict resolution

**Key Features**:
- Analyzes Dockerfile and requirements.txt
- Detects PyTorch/CUDA mismatches
- Auto-fixes dependency conflicts
- Smart base image selection
- Auto-rebuild on failure (max 3 attempts)

**Usage**:
```bash
/build-docker-image [--dockerfile path] [--auto_fix] [--verbose]
```

**Example**:
```bash
/build-docker-image --dockerfile Dockerfile --tag myapp:v1.0 --auto_fix=true
```

### 2. Docker Image Tester

**Purpose**: Comprehensive testing with fix recommendations

**Key Features**:
- Import testing (PyTorch, Transformers, etc.)
- Model configuration validation
- Model instantiation tests
- Forward pass execution
- Generates fix recommendations
- Creates detailed reports

**Usage**:
```bash
/test-docker-image [--image name] [--level quick|standard|full]
```

**Example**:
```bash
/test-docker-image --image pytorch-fsdp:latest --level standard
```

### 3. ECR Image Pusher

**Purpose**: Push images to Amazon ECR

**Key Features**:
- Auto-discovers ECR repositories
- Multiple tagging strategies
- Semantic versioning support
- Push verification
- Multi-region support

**Usage**:
```bash
/push-to-ecr [--repository name] [--tags strategy] [--region us-west-2]
```

**Example**:
```bash
/push-to-ecr --repository fsdp --tags semantic --region us-west-2
```

## Integration with CI/CD

### AWS CodeBuild

The `buildspec.yml` in the project root orchestrates all three skills:

```yaml
phases:
  build:
    commands:
      - /build-docker-image
  post_build:
    commands:
      - /test-docker-image
      - /push-to-ecr
```

### GitHub Actions

```yaml
- name: Build, Test, and Push
  run: |
    opencode /build-docker-image
    opencode /test-docker-image
    opencode /push-to-ecr
```

## Troubleshooting

### Build Failures

Check build logs:
```bash
opencode /build-docker-image --verbose=true
```

### Test Failures

Review test reports:
```bash
ls -la test-reports/
cat test-reports/test-report-*.json
```

### Push Failures

Verify AWS credentials:
```bash
aws sts get-caller-identity
aws ecr describe-repositories
```

## Customization

### Override Global Skills

Copy global skill to project:
```bash
cp -r ~/.opencode/skills/docker-image-builder .opencode/skills/
```

Modify for project-specific needs.

### Custom Test Suite

Edit `.opencode/skills/docker-image-tester/src/test_suite.py` to add custom tests.

### Custom Tagging Strategy

Edit `.opencode/skills/ecr-image-pusher/src/version_manager.py` to add custom strategies.

## Support

For issues or questions:
1. Check skill README files in `~/.opencode/skills/<skill-name>/`
2. Review logs in test-reports/
3. Open an issue in the project repository

## License

MIT
