# ECR Image Pusher Skill

Securely pushes Docker images to Amazon ECR with automatic repository discovery, semantic versioning, and push verification.

## Features

- 🔐 **Secure Authentication**: Automatic ECR login with AWS credentials
- 🏷️ **Smart Tagging**: Multiple tagging strategies (auto, semantic, git-sha)
- 📦 **Repository Management**: Auto-create repositories if needed
- ✅ **Push Verification**: Confirm images are in registry
- 🌍 **Multi-Region**: Support for cross-region pushes
- 📊 **Detailed Logging**: Real-time push progress and status

## Usage

### Command Line

```bash
# Basic push
python src/push_image.py

# Push specific image
python src/push_image.py --image myapp:v1.0 --repository production

# Push with semantic versioning
python src/push_image.py --tags semantic

# Push to different region
python src/push_image.py --region us-east-1
```

### As a Skill

```bash
# Trigger via opencode
/push-to-ecr

# Push with specific options
/push-to-ecr --image pytorch-fsdp:latest --tags semantic --region us-west-2

# Push to production
/push-to-ecr --repository fsdp-production --tags latest
```

## Tagging Strategies

### Auto (Default)
Intelligently generates tags based on git state:
- Git tag → `v1.2.3`, `latest`
- Git commit → `abc1234`
- Branch name → `feature-branch` (if not main/master)
- Timestamp → `20240213-143022` (always included)

### Semantic
Semantic versioning with aliases:
- Full version: `1.2.3`
- Minor version: `1.2`
- Major version: `1`
- Latest: `latest`

### Latest
Only `latest` tag (simplest approach)

### Git-SHA
Commit-based tags:
- Short SHA: `abc1234`
- Prefixed: `sha-abc1234`

## Configuration

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `image` | string | `""` | Image to push (auto-detect if empty) |
| `repository` | string | `fsdp` | ECR repository name |
| `region` | string | `us-west-2` | AWS region |
| `profile` | string | `""` | AWS profile name |
| `tags` | string | `auto` | Tagging strategy |
| `create_repository` | boolean | `true` | Create repo if not exists |
| `verify_push` | boolean | `true` | Verify after push |
| `verbose` | boolean | `true` | Show detailed output |
| `use_sudo` | boolean | `false` | Use sudo for Docker |

## Prerequisites

### AWS Credentials
Configure AWS CLI:
```bash
aws configure
# or
aws configure --profile myprofile
```

Required IAM permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:CreateRepository",
        "ecr:DescribeRepositories",
        "ecr:DescribeImages"
      ],
      "Resource": "*"
    }
  ]
}
```

## Output

### Console Output
```
============================================================
ECR Image Pusher
============================================================
Repository: fsdp
Region: us-west-2
Tag strategy: auto

============================================================
Prerequisites
============================================================
✅ Docker installed
✅ AWS credentials valid

============================================================
ECR Repository
============================================================
🔍 Checking repository: fsdp
✅ Repository exists: 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp

============================================================
Authentication
============================================================
🔐 Authenticating with ECR...
✅ Authenticated with ECR

============================================================
Tagging
============================================================
Using tagging strategy: auto (Auto-detect from git)
Tags to apply: 20240213-143022, v1.2.3, latest, abc1234
🏷️  Tagging: pytorch-fsdp:latest → 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:20240213-143022
✅ Tagged: 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:20240213-143022
...

============================================================
Pushing Images to ECR
============================================================
📤 Pushing: 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:20240213-143022
[=================>] 100% 3.54 GB/3.54 GB
✅ Pushed: 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:20240213-143022
...

============================================================
Push Summary
============================================================
✅ Repository: 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp
Tags pushed: 20240213-143022, v1.2.3, latest, abc1234
Push time: 145.2s
🎉 Push completed successfully!
```

### JSON Result
```json
{
  "success": true,
  "repository_uri": "975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp",
  "tags_pushed": ["20240213-143022", "v1.2.3", "latest", "abc1234"],
  "push_time": "145.2s",
  "region": "us-west-2"
}
```

## Examples

### Example 1: First Push
```bash
$ /push-to-ecr --repository myapp
🔍 Checking repository: myapp
ℹ️  Repository not found, creating...
✅ Created ECR repository: myapp
...
🎉 Push completed successfully!
```

### Example 2: Semantic Versioning
```bash
$ git tag -a v2.0.0 -m "Release 2.0.0"
$ /push-to-ecr --tags semantic
Using tagging strategy: semantic (Semantic versioning)
Tags to apply: 2.0.0, 2.0, 2, latest
...
✅ Pushed all tags
```

### Example 3: Multi-Region Push
```bash
# Push to us-west-2
/push-to-ecr --region us-west-2

# Push to us-east-1
/push-to-ecr --region us-east-1

# Push to eu-west-1
/push-to-ecr --region eu-west-1
```

## Architecture

```
push_image.py
├── VersionManager
│   ├── get_git_info()
│   ├── generate_tags_auto()
│   ├── generate_tags_semantic()
│   ├── generate_tags_latest()
│   └── generate_tags_git_sha()
├── TagStrategy (dataclass)
└── ECRImagePusher (main)
    ├── validate_prerequisites()
    ├── get_image_to_push()
    ├── setup_ecr_repository()
    ├── authenticate_with_ecr()
    ├── tag_image()
    ├── push_images()
    ├── verify_push()
    └── run()
```

## Integration with CI/CD

### CodeBuild
```yaml
post_build:
  commands:
    - python src/push_image.py --repository $ECR_REPO --region $AWS_REGION
```

### GitHub Actions
```yaml
- name: Push to ECR
  run: |
    python src/push_image.py \
      --image myapp:${{ github.sha }} \
      --tags git-sha
```

### GitLab CI
```yaml
push:
  script:
    - python src/push_image.py --tags semantic
```

## Troubleshooting

### Authentication Failed
```
❌ Failed to authenticate with ECR
```
**Fix**: Check AWS credentials
```bash
aws sts get-caller-identity
aws ecr get-login-password --region us-west-2
```

### Repository Not Found
```
❌ Repository does not exist: myrepo
```
**Fix**: Enable auto-create or create manually
```bash
# Option 1: Enable auto-create
/push-to-ecr --create_repository=true

# Option 2: Create manually
aws ecr create-repository --repository-name myrepo
```

### Push Failed
```
❌ Failed to push: image:tag
```
**Fix**: Check network and permissions
```bash
# Test connectivity
aws ecr describe-repositories

# Check Docker
docker info
```

## Best Practices

1. **Use Semantic Versioning**: For production releases
2. **Tag with Git SHA**: For traceability
3. **Always Verify**: Enable `--verify_push` for critical images
4. **Multi-Region**: Push to multiple regions for HA
5. **Clean Up**: Remove old tags to save storage costs

## Cost Considerations

- **Storage**: $0.10 per GB-month
- **Data Transfer**: Free within same region
- **API Calls**: $0.004 per 1,000 requests

## License

MIT
