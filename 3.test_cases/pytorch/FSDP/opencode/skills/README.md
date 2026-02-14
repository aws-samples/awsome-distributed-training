# Opencode Skills - Docker & ECR Automation

A comprehensive suite of autonomous skills for Docker image management and AWS ECR operations.

## Skills Overview

### 🔨 docker-image-builder
Intelligently builds Docker images with automatic conflict detection and resolution.

**Capabilities**:
- Analyzes Dockerfile and requirements.txt for compatibility issues
- Detects PyTorch/CUDA version mismatches
- Auto-fixes dependency conflicts
- Smart base image selection
- Auto-rebuild on failure (max 3 attempts)
- Real-time status updates

**Location**: `docker-image-builder/`

### 🧪 docker-image-tester
Comprehensive testing framework with automatic fix recommendations.

**Capabilities**:
- Multiple test levels (quick, standard, full)
- Import testing for all dependencies
- Model configuration validation
- Model instantiation and forward pass tests
- Generates detailed test reports
- Provides fix recommendations for failures

**Location**: `docker-image-tester/`

### 🚀 ecr-image-pusher
Securely pushes Docker images to Amazon ECR.

**Capabilities**:
- Automatic ECR repository discovery
- Multiple tagging strategies (auto, semantic, git-sha)
- Semantic versioning support
- Push verification
- Multi-region support
- AWS credential management

**Location**: `ecr-image-pusher/`

## Shared Utilities

Common utilities used by all skills:

- **aws_utils.py** - AWS API helpers (ECR, S3, CodeBuild)
- **docker_utils.py** - Docker operations and analysis
- **logger.py** - Consistent logging and status reporting

**Location**: `shared/`

## Infrastructure Templates

Ready-to-use infrastructure as code:

### AWS CLI Setup Script
One-command setup using AWS CLI:
```bash
infrastructure/aws-cli/setup-codebuild.sh \
  --project-name pytorch-fsdp \
  --repository-name fsdp \
  --region us-west-2
```

### CloudFormation Template
Deploy using CloudFormation:
```bash
aws cloudformation create-stack \
  --stack-name pytorch-fsdp \
  --template-file infrastructure/cloudformation/fsdp-codebuild.yaml \
  --parameters file://infrastructure/cloudformation/parameters.json
```

### Terraform Module
Deploy using Terraform:
```bash
cd infrastructure/terraform
terraform init
terraform apply
```

## Installation

### Automatic Installation

The skills are automatically available when using opencode with the proper configuration.

### Manual Installation

1. Clone or copy skills to `~/.opencode/skills/`
2. Ensure Python 3.8+ is installed
3. Install dependencies: `pip install boto3 awscli`

### Project-Specific Setup

Copy skills to your project:
```bash
mkdir -p .opencode/skills
cp -r ~/.opencode/skills/* .opencode/skills/
```

## Usage

### Command Line

Each skill can be run standalone:

```bash
# Build
python3 ~/.opencode/skills/docker-image-builder/src/build_image.py \
  --dockerfile Dockerfile --auto_fix

# Test
python3 ~/.opencode/skills/docker-image-tester/src/test_image.py \
  --image myapp:latest --level standard

# Push
python3 ~/.opencode/skills/ecr-image-pusher/src/push_image.py \
  --repository fsdp --tags auto
```

### As Opencode Skills

Trigger via opencode commands:

```bash
/build-docker-image --dockerfile Dockerfile --verbose
/test-docker-image --image myapp:latest --level full
/push-to-ecr --repository fsdp --region us-west-2
```

## Configuration

### Environment Variables

```bash
# AWS
AWS_PROFILE=default
AWS_REGION=us-west-2

# Docker
DOCKERFILE=Dockerfile
BUILD_CONTEXT=.

# Testing
TEST_LEVEL=standard
GENERATE_REPORT=true

# ECR
ECR_REPOSITORY=fsdp
TAG_STRATEGY=auto
```

### Skill Configuration Files

Each skill has a `skill.yaml` with:
- Parameters and defaults
- Trigger patterns
- Dependencies
- Examples

## Architecture

```
~/.opencode/skills/
├── docker-image-builder/
│   ├── skill.yaml
│   ├── src/
│   │   ├── build_image.py
│   │   ├── conflict_analyzer.py
│   │   ├── base_image_selector.py
│   │   └── smoke_test.py
│   └── README.md
├── docker-image-tester/
│   ├── skill.yaml
│   ├── src/
│   │   └── test_image.py
│   └── README.md
├── ecr-image-pusher/
│   ├── skill.yaml
│   ├── src/
│   │   └── push_image.py
│   └── README.md
├── shared/
│   ├── __init__.py
│   ├── aws_utils.py
│   ├── docker_utils.py
│   └── logger.py
└── infrastructure/
    ├── aws-cli/
    ├── cloudformation/
    └── terraform/
```

## Development

### Adding New Tests

Edit `docker-image-tester/src/test_image.py`:

```python
def test_my_custom_test(self) -> TestCase:
    test = TestCase(
        name="my_test",
        category="custom",
        description="My custom test"
    )
    # Test logic here
    return test
```

### Adding New Tagging Strategies

Edit `ecr-image-pusher/src/push_image.py`:

```python
def generate_tags_custom(self, image_name: str) -> List[str]:
    return ["custom-tag-1", "custom-tag-2"]
```

### Adding New Conflict Detectors

Edit `docker-image-builder/src/conflict_analyzer.py`:

```python
def check_my_conflict(self, line: str, line_num: int):
    if "some-pattern" in line:
        issues.append({
            'type': 'my_conflict',
            'message': 'Description of issue'
        })
```

## Testing

Run skill tests:

```bash
# Test conflict analyzer
python3 docker-image-builder/src/conflict_analyzer.py Dockerfile requirements.txt

# Test base image selector
python3 docker-image-builder/src/base_image_selector.py 2.5

# Test smoke tester
python3 docker-image-builder/src/smoke_test.py myimage:latest
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

MIT License - See individual skill README files for details.

## Support

For issues, questions, or contributions:
- Check individual skill README files
- Review logs and test reports
- Open an issue in the repository

---

**Built with ❤️ for the PyTorch FSDP community**
