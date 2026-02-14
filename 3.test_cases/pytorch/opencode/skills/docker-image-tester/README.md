# Docker Image Tester Skill

Comprehensive testing framework for Docker images with automatic fix recommendations.

## Features

- 🧪 **Multiple Test Levels**: Quick, Standard, and Full testing
- 📊 **Detailed Reports**: JSON/HTML test reports with full details
- 🔍 **Import Testing**: Validates all required packages
- 🤖 **Model Testing**: Tests model configuration and instantiation
- 💡 **Fix Recommendations**: Automatic suggestions for failures
- 📈 **Test Metrics**: Pass/fail rates and performance data

## Usage

### Command Line

```bash
# Basic test
python src/test_image.py

# Test specific image
python src/test_image.py --image myapp:v1.0

# Full test suite
python src/test_image.py --level full

# Generate HTML report
python src/test_image.py --report_format html
```

### As a Skill

```bash
# Trigger via opencode
/test-docker-image

# Test specific image with full suite
/test-docker-image --image pytorch-fsdp:latest --level full

# Quick test without report
/test-docker-image --level quick --generate_report=false
```

## Test Levels

### Quick (~2 minutes)
- Basic imports (torch, transformers, datasets)
- Package version verification

### Standard (~5 minutes) ⭐ Default
- All Quick tests
- CUDA availability check
- FSDP model utils import
- Model configuration creation
- Model instantiation (59M params)

### Full (~10 minutes)
- All Standard tests
- Forward pass execution
- Dataset loading
- Checkpoint operations
- Memory usage validation

## Test Categories

| Category | Tests | Description |
|----------|-------|-------------|
| imports | basic_imports, version_check | Package import validation |
| hardware | cuda_available | GPU/CUDA detection |
| fsdp | model_utils_import | FSDP utilities |
| model | model_config, model_instantiation, forward_pass | Model operations |

## Configuration

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `image` | string | `""` | Image to test (auto-detect if empty) |
| `level` | string | `standard` | Test level: quick/standard/full |
| `generate_report` | boolean | `true` | Generate test report |
| `report_format` | string | `json` | Report format: json/html/both |
| `output_dir` | string | `./test-reports` | Report output directory |
| `verbose` | boolean | `true` | Show detailed output |
| `use_sudo` | boolean | `false` | Use sudo for Docker |

## Output

### Console Output
```
============================================================
Docker Image Tester
============================================================
Testing image: pytorch-fsdp:20240213-143022
Test level: standard

============================================================
Test Results
============================================================
✅ basic_imports: All basic imports successful
✅ version_check: Versions: {'torch': '2.5.1', ...}
⚠️  cuda_available: CUDA not available (CPU-only mode)
✅ model_utils_import: Model utils imported successfully
✅ model_config: Model config created
✅ model_instantiation: Model created: 59,247,104 parameters (59.2M)

============================================================
Fix Recommendations
============================================================
⚠️ [MEDIUM] CUDA not available
   Recommendation: Image is CPU-only. For GPU training, use CUDA-enabled base image
   Example: FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

============================================================
Test Summary
============================================================
Total: 6
Passed: 5 ✅
Failed: 0
Success rate: 83.3%
```

### JSON Report
```json
{
  "image": "pytorch-fsdp:20240213-143022",
  "timestamp": "2024-02-13T14:30:22.123456",
  "summary": {
    "total": 6,
    "passed": 5,
    "failed": 0,
    "success_rate": 83.3,
    "recommendations_count": 1
  },
  "tests": [
    {
      "name": "basic_imports",
      "category": "imports",
      "description": "Test basic package imports",
      "passed": true,
      "message": "All basic imports successful",
      "duration_ms": 0
    }
  ],
  "recommendations": [
    {
      "issue": "CUDA not available",
      "severity": "medium",
      "recommendation": "Image is CPU-only...",
      "code_example": "FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime"
    }
  ]
}
```

## Fix Recommendations

The skill automatically generates recommendations for common issues:

### Critical Issues
- Import failures → Check requirements.txt
- Model utils import failed → Verify COPY command in Dockerfile

### High Priority
- Model instantiation failed → Check memory and configuration

### Medium Priority
- CUDA not available → Use CUDA-enabled base image
- Version mismatches → Update package versions

### Low Priority
- Missing optimization flags → Add --no-cache-dir

## Integration with CI/CD

### CodeBuild Integration
```yaml
post_build:
  commands:
    - python src/test_image.py --image $IMAGE_NAME --level standard
    - |
      if [ $? -ne 0 ]; then
        echo "Tests failed, check test-reports/"
        exit 1
      fi
```

### GitHub Actions
```yaml
- name: Test Docker Image
  run: |
    python src/test_image.py --image myapp:${{ github.sha }}
```

## Architecture

```
test_image.py
├── TestCase (dataclass)
├── FixRecommendation (dataclass)
├── TestSuite
│   ├── test_imports_basic()
│   ├── test_imports_versions()
│   ├── test_cuda_availability()
│   ├── test_model_utils_import()
│   ├── test_model_config_creation()
│   ├── test_model_instantiation()
│   ├── test_forward_pass()
│   └── run_tests()
└── ImageTester (main)
    ├── get_image_to_test()
    └── run()
```

## Examples

### Example 1: All Tests Pass
```bash
$ /test-docker-image --level standard
============================================================
Test Results
============================================================
✅ basic_imports: All basic imports successful
✅ version_check: Versions: {'torch': '2.5.1', ...}
✅ cuda_available: CUDA available: 12.4
✅ model_utils_import: Model utils imported successfully
✅ model_config: Model config created
✅ model_instantiation: Model created: 59,247,104 parameters (59.2M)

============================================================
Test Summary
============================================================
Total: 6
Passed: 6 ✅
Success rate: 100.0%
✅ Report saved: ./test-reports/test-report-20240213-143022.json
🎉 All tests passed!
```

### Example 2: Tests with Warnings
```bash
$ /test-docker-image --level standard
...
⚠️  cuda_available: CUDA not available (CPU-only mode)
...
⚠️ [MEDIUM] CUDA not available
   Recommendation: Image is CPU-only. For GPU training, use CUDA-enabled base image
...
Success rate: 83.3%
```

## Troubleshooting

### Test Timeouts
Increase timeout for slow tests:
```python
# In test_image.py, increase timeout
success, stdout, stderr = self._run_in_container(code, timeout=300)
```

### Memory Issues
For large model tests, ensure sufficient memory:
```bash
docker run --memory=8g myimage tests
```

## Dependencies

- Docker
- Python 3.8+
- Tested image with Python environment

## License

MIT
