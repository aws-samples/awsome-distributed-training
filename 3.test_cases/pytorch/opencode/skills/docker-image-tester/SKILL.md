---
name: docker-image-tester
description: Test Docker images using CodeBuild (default - no local Docker required) or local Docker. Supports multiple test levels (quick, standard, full) for validating PyTorch/CUDA compatibility, imports, and model functionality.
license: MIT
compatibility: opencode
metadata:
  category: testing
  author: opencode
  default_mode: codebuild
---

## What I do

Test Docker images using **AWS CodeBuild** (default - no local Docker required!) or local Docker:

### CodeBuild Mode (Default - Recommended)
1. **No Local Docker Required**: Tests run entirely in AWS CodeBuild
2. **Multiple Test Levels**: quick, standard, or full validation
3. **Automatic Execution**: Tests run in clean, isolated environment
4. **Real Results**: Tests actually import and run code from the image

### Local Mode (Optional)
1. **Import Tests**: Verify all Python packages import correctly
2. **CUDA Tests**: Check GPU availability and CUDA compatibility
3. **Model Tests**: Load model configurations and instantiate models
4. **Forward Pass**: Execute inference to validate functionality

## When to use me

Use this skill when you need to:
- **Test a Docker image without installing Docker locally** (use CodeBuild mode)
- Validate a Docker image before deployment
- Check PyTorch/CUDA compatibility
- Test model loading and inference
- Generate test reports for CI/CD

## How to use me

### CodeBuild Mode (Default - No Docker Required!)

```bash
# Quick test (imports only) - FASTEST
python3 opencode/skills/docker-image-tester/src/test_image_codebuild.py \
  --image 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest \
  --level quick

# Standard test (imports + CUDA + model config)
python3 opencode/skills/docker-image-tester/src/test_image_codebuild.py \
  --image 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest \
  --level standard

# Full test (all tests)
python3 opencode/skills/docker-image-tester/src/test_image_codebuild.py \
  --image 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest \
  --level full \
  --wait
```

### Prerequisites for CodeBuild Mode

1. **AWS CLI configured**:
   ```bash
   aws configure
   ```

2. **CodeBuild project exists**:
   ```bash
   # Using the setup script
   ./opencode/skills/infrastructure/aws-cli/setup-codebuild.sh \
     --project-name pytorch-fsdp \
     --region us-west-2
   ```

### Local Mode (Requires Docker)

```bash
# Force local testing (requires Docker installed)
python3 opencode/skills/docker-image-tester/src/test_image.py \
  --use-local \
  --image fsdp:latest \
  --level standard
```

## Test Levels

### CodeBuild Test Levels

- **quick** (~2-3 minutes): Basic imports only
  - Import torch, transformers, datasets
  - Fast validation that image works
  
- **standard** (~5-7 minutes): Imports + CUDA + model config
  - All quick tests
  - Check CUDA availability
  - Load model configurations
  - Validate datasets
  
- **full** (~10-15 minutes): All tests including model loading
  - All standard tests
  - Instantiate models
  - Run forward pass
  - Comprehensive validation

### Local Test Levels

- **quick**: Basic imports only (~30 seconds)
- **standard**: Imports + CUDA + model config (~60 seconds)
- **full**: All tests including forward pass (~120 seconds)

## Parameters

### CodeBuild Mode Parameters

- `--use-codebuild`: Use CodeBuild (default: True)
- `--image`: Docker image URI to test (required)
  - Format: `ACCOUNT.dkr.ecr.REGION.amazonaws.com/REPOSITORY:TAG`
  - Example: `975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest`
- `--level`: Test level - quick, standard, or full (default: "standard")
- `--region`: AWS region (default: "us-west-2")
- `--wait`: Wait for test completion (default: True)
- `--no-wait`: Don't wait, run in background
- `--timeout`: Test timeout in seconds (default: 600)
- `--verbose`: Show detailed output (default: true)

### Local Mode Parameters

- `--use-local`: Use local Docker instead of CodeBuild
- `--image`: Docker image name to test (required)
- `--level`: Test level - quick, standard, or full (default: "standard")
- `--generate_report`: Generate JSON test report (default: true)
- `--output_dir`: Directory for test reports (default: "./test-reports")
- `--verbose`: Show detailed output (default: true)

## Output

### CodeBuild Mode Output

Returns a dictionary with:
- `success`: Boolean indicating test status
- `image`: Tested image URI
- `build_id`: CodeBuild build ID for logs
- `tests`: List of test cases with results
- `message`: Status message

### Local Mode Output

Generates:
- Console output with test results
- JSON report with detailed results
- Fix recommendations for failed tests

## Examples

### Example 1: Quick CodeBuild Test

```bash
# Fast validation - just imports
python3 opencode/skills/docker-image-tester/src/test_image_codebuild.py \
  --image 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest \
  --level quick
```

**What happens:**
1. Triggers CodeBuild with the image URI
2. Runs import tests inside CodeBuild
3. Reports success/failure

### Example 2: Standard Test with Monitoring

```bash
# Full validation with progress monitoring
python3 opencode/skills/docker-image-tester/src/test_image_codebuild.py \
  --image 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest \
  --level standard \
  --wait
```

### Example 3: Background Test

```bash
# Start test without waiting
python3 opencode/skills/docker-image-tester/src/test_image_codebuild.py \
  --image 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest \
  --level full \
  --no-wait

# Later, check status:
aws codebuild batch-get-builds \
  --ids pytorch-fsdp:<build-id-from-output> \
  --region us-west-2
```

### Example 4: Local Docker Test (If You Have Docker)

```bash
# Only if you have Docker installed locally
python3 opencode/skills/docker-image-tester/src/test_image.py \
  --use-local \
  --image fsdp:latest \
  --level standard \
  --generate_report true
```

## Complete Workflow

```bash
# 1. Build image using CodeBuild
python3 opencode/skills/docker-image-builder/src/build_image_codebuild.py \
  --codebuild-project pytorch-fsdp

# 2. Test the built image using CodeBuild (NO LOCAL DOCKER!)
python3 opencode/skills/docker-image-tester/src/test_image_codebuild.py \
  --image 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest \
  --level standard

# 3. Deploy training job
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

### "Image not found"

Make sure the image URI is correct:
```bash
# Verify image exists in ECR
aws ecr describe-images \
  --repository-name fsdp \
  --region us-west-2
```

### "Test failed"

Check CloudWatch logs:
```bash
aws logs tail /aws/codebuild/pytorch-fsdp --follow
```

### "AWS credentials not configured"

Configure AWS CLI:
```bash
aws configure
```

## Why CodeBuild for Testing?

**Advantages over local Docker testing:**
- ✅ **No local Docker required**: Tests run entirely in AWS
- ✅ **Clean environment**: Fresh environment for each test
- ✅ **Scalable**: Run multiple tests in parallel
- ✅ **Real validation**: Actually pulls and runs the image
- ✅ **Integrated logging**: All logs in CloudWatch
- ✅ **No resource constraints**: Not limited by local machine

**Test Duration:**
- Quick tests: ~2-3 minutes
- Standard tests: ~5-7 minutes
- Full tests: ~10-15 minutes

**Cost:**
- ~$0.05-0.15 per test (depending on level)
- Much cheaper than maintaining an EC2 instance for testing

## Comparison: CodeBuild vs Local vs EC2

| Method | Docker Required | Setup Complexity | Cost | Speed |
|--------|----------------|------------------|------|-------|
| **CodeBuild** | ❌ No | 🟢 Low | 🟢 Pay per use | 🟡 2-15 min |
| **Local Docker** | ✅ Yes | 🟢 Low | 🟢 Free | 🟢 30s-2min |
| **EC2 Instance** | ❌ No | 🟡 Medium | 🔴 Hourly | 🟢 Fast |

**Recommendation**: Use CodeBuild for CI/CD and when you don't have Docker locally. Use local Docker only for rapid development iteration.
