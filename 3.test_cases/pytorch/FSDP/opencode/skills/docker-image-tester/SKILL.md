---
name: docker-image-tester
description: Test Docker images with comprehensive validation including import tests, CUDA checks, model configuration loading, and forward pass execution. Generates detailed reports and fix recommendations.
license: MIT
compatibility: opencode
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

## How to use me

### Command Line
```bash
# Quick test (imports only)
python3 ~/.opencode/skills/docker-image-tester/src/test_image.py --image fsdp:latest --level quick

# Standard test (imports + CUDA + model config)
python3 ~/.opencode/skills/docker-image-tester/src/test_image.py --image fsdp:latest --level standard

# Full test (all tests including forward pass)
python3 ~/.opencode/skills/docker-image-tester/src/test_image.py --image fsdp:latest --level full
```

### Python API
```python
from docker_image_tester.src.test_image import TestSuite

suite = TestSuite(image_name="fsdp:latest", docker_client=docker, logger=logger)
tests = suite.run_all_tests()
```

## Test Levels

- **quick**: Basic imports only (~30 seconds)
- **standard**: Imports + CUDA + model config (~60 seconds)
- **full**: All tests including forward pass (~120 seconds)

## Parameters

- `image`: Docker image name to test (required)
- `level`: Test level - quick, standard, or full (default: "standard")
- `generate_report`: Generate JSON test report (default: true)
- `output_dir`: Directory for test reports (default: "./test-reports")
- `verbose`: Show detailed output (default: true)

## Output

Generates:
- Console output with test results
- JSON report with detailed results
- Fix recommendations for failed tests

## Examples

### Quick validation
```bash
python3 ~/.opencode/skills/docker-image-tester/src/test_image.py --image fsdp:latest --level quick
```

### Full test with report
```bash
python3 ~/.opencode/skills/docker-image-tester/src/test_image.py \
  --image fsdp:latest \
  --level full \
  --generate_report true \
  --output_dir ./test-reports
```
