---
name: docker-image-tester
description: Test Docker images with comprehensive validation using CodeBuild (no local Docker required) or local Docker. Supports import tests, CUDA checks, model configuration loading, and forward pass execution. Generates detailed reports and fix recommendations.
license: MIT
compatibility: kiro
metadata:
  category: testing
  author: opencode
---

## What I do

Comprehensive Docker image testing with multiple validation levels:

1. **Import Tests**: Verify all Python packages import correctly
2. **CUDA Tests**: Check GPU availability and CUDA compatibility
3. **Model Tests**: Load model configurations and instantiate models
4. **Forward Pass**: Execute inference to validate functionality
5. **FSDP Tests**: Verify distributed training compatibility

## When to use me

Use this skill when you need to:
- Validate a Docker image before deployment
- Check PyTorch/CUDA compatibility
- Test model loading and inference
- Verify FSDP (Fully Sharded Data Parallel) setup
- Generate test reports for CI/CD
- Test images without local Docker installation

## How to use me

### Command Line

#### CodeBuild Testing (No Local Docker Required)
```bash
# Quick test (imports only)
python3 ~/.opencode/skills/docker-image-tester/src/test_image_codebuild.py \
  --image 123456789.dkr.ecr.us-west-2.amazonaws.com/myimage:latest \
  --level quick

# Standard test with custom project
python3 ~/.opencode/skills/docker-image-tester/src/test_image_codebuild.py \
  --image 123456789.dkr.ecr.us-west-2.amazonaws.com/myimage:latest \
  --project my-codebuild-project \
  --level standard

# Full test with custom bucket
python3 ~/.opencode/skills/docker-image-tester/src/test_image_codebuild.py \
  --image 123456789.dkr.ecr.us-west-2.amazonaws.com/myimage:latest \
  --level full \
  --bucket my-test-bucket
```

#### Local Docker Testing
```bash
# Quick test (imports only)
python3 ~/.opencode/skills/docker-image-tester/src/test_image.py \
  --image fsdp:latest --level quick

# Standard test (imports + CUDA + model config)
python3 ~/.opencode/skills/docker-image-tester/src/test_image.py \
  --image fsdp:latest --level standard

# Full test (all tests including forward pass)
python3 ~/.opencode/skills/docker-image-tester/src/test_image.py \
  --image fsdp:latest --level full
```

### Python API
```python
from docker_image_tester.src.test_image_codebuild import CodeBuildTester

# Test with CodeBuild
tester = CodeBuildTester(logger, region="us-west-2", project_name="my-project")
success, build_id = tester.run_test(
    image_uri="123456789.dkr.ecr.us-west-2.amazonaws.com/myimage:latest",
    test_level="standard"
)

# Wait for results
success, message, tests = tester.wait_for_test(build_id, timeout=600)
```

## Test Levels

- **quick**: Basic imports only (~30 seconds)
- **standard**: Imports + CUDA + VERL + model packages (~5-8 minutes)
- **full**: All tests including model loading (~10-15 minutes)

## Parameters

### CodeBuild Testing

- `image`: Docker image URI to test (required)
- `project`: CodeBuild project name (default: "verl-rlvr")
- `bucket`: S3 bucket for test source (auto-detected if not specified)
- `level`: Test level - quick, standard, or full (default: "standard")
- `region`: AWS region (default: "us-west-2")
- `wait`: Wait for test completion (default: True)
- `timeout`: Test timeout in seconds (default: 600)
- `verbose`: Show detailed output (default: True)

### Local Docker Testing

- `image`: Docker image name to test (required)
- `level`: Test level - quick, standard, or full (default: "standard")
- `generate_report`: Generate JSON test report (default: true)
- `output_dir`: Directory for test reports (default: "./test-reports")
- `verbose`: Show detailed output (default: true)

## How CodeBuild Testing Works

1. **Creates test buildspec**: Generates a buildspec.yml with test commands
2. **Packages source**: Creates a zip file containing the buildspec
3. **Uploads to S3**: Uploads the zip to the project's S3 bucket
4. **Updates project**: Temporarily updates CodeBuild project to use test source
5. **Runs tests**: Triggers CodeBuild with the test configuration
6. **Monitors progress**: Waits for build completion and captures results
7. **Restores config**: Automatically restores original project configuration
8. **Reports results**: Displays test results and logs

## Output

Generates:
- Console output with test results
- JSON report with detailed results
- CloudWatch logs from CodeBuild
- Fix recommendations for failed tests

## Examples

### Test ECR image with CodeBuild
```bash
python3 ~/.opencode/skills/docker-image-tester/src/test_image_codebuild.py \
  --image 975049888767.dkr.ecr.us-west-2.amazonaws.com/verl-rlvr:latest \
  --project verl-rlvr \
  --level standard \
  --wait
```

### Quick validation without waiting
```bash
python3 ~/.opencode/skills/docker-image-tester/src/test_image_codebuild.py \
  --image 975049888767.dkr.ecr.us-west-2.amazonaws.com/verl-rlvr:latest \
  --level quick \
  --no-wait
```

### Full test with custom bucket
```bash
python3 ~/.opencode/skills/docker-image-tester/src/test_image_codebuild.py \
  --image 975049888767.dkr.ecr.us-west-2.amazonaws.com/verl-rlvr:latest \
  --level full \
  --bucket my-custom-bucket \
  --timeout 900
```

## Requirements

### For CodeBuild Testing
- AWS CLI configured with appropriate credentials
- CodeBuild project exists
- S3 bucket for build artifacts (auto-detected)
- ECR repository with image

### For Local Docker Testing
- Docker installed and running
- Image available locally

## Notes

- CodeBuild testing requires a CodeBuild project to exist
- The skill temporarily modifies the project's source configuration
- Original configuration is automatically restored after testing
- Test source packages are uploaded to S3 with timestamps
- Large images may take 5-15 minutes to test depending on size
