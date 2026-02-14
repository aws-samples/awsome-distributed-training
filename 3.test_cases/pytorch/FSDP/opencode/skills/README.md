# OpenCode Skills for PyTorch FSDP

A comprehensive suite of skills for building, testing, and deploying PyTorch FSDP training workloads on Amazon EKS using OpenCode.

## 📦 Available Skills

| Skill | Purpose | Location |
|-------|---------|----------|
| **docker-image-builder** | Build Docker images with auto-fix | `docker-image-builder/` |
| **docker-image-tester** | Test Docker images | `docker-image-tester/` |
| **ecr-image-pusher** | Push images to ECR | `ecr-image-pusher/` |
| **eks-cluster-manager** | Manage EKS clusters | `eks-cluster-manager/` |
| **training-job-deployer** | Deploy training jobs | `training-job-deployer/` |

## 🚀 Quick Start

### Installation

Copy skills to your OpenCode skills directory:

```bash
# Create skills directory
mkdir -p ~/.config/opencode/skills

# Copy all skills from this repo
cp -r /path/to/repo/opencode/skills/* ~/.config/opencode/skills/

# Or copy specific skills
cp -r opencode/skills/docker-image-builder ~/.config/opencode/skills/
cp -r opencode/skills/training-job-deployer ~/.config/opencode/skills/
```

### Usage

Once installed, OpenCode automatically discovers these skills.

**Using the skill tool:**
```python
# Load a skill
skill("docker-image-builder")

# Or reference in conversation:
"Build a Docker image for PyTorch FSDP training"
```

**Direct execution:**
```bash
# Build Docker image
python3 ~/.config/opencode/skills/docker-image-builder/src/build_image.py --auto_fix

# Deploy training job
python3 ~/.config/opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster --num_nodes 4
```

## 📖 Skill Details

### Docker Image Builder

Builds Docker images with automatic conflict detection and resolution.

**Features:**
- PyTorch/CUDA compatibility analysis
- Auto-fix dependency conflicts
- Smart base image selection
- Retry logic (up to 3 attempts)

**Files:**
- `SKILL.md` - OpenCode skill definition
- `src/build_image.py` - Main builder
- `src/conflict_analyzer.py` - Conflict detection
- `src/base_image_selector.py` - Base image selection
- `src/smoke_test.py` - Quick validation

**Usage:**
```bash
python3 opencode/skills/docker-image-builder/src/build_image.py \
  --dockerfile Dockerfile \
  --auto_fix true
```

### Docker Image Tester

Comprehensive Docker image testing framework.

**Features:**
- Multiple test levels (quick, standard, full)
- Import validation
- CUDA availability checks
- Model configuration tests
- Forward pass validation

**Files:**
- `SKILL.md` - Skill definition
- `src/test_image.py` - Test suite

**Usage:**
```bash
python3 opencode/skills/docker-image-tester/src/test_image.py \
  --image fsdp:latest \
  --level full
```

### ECR Image Pusher

Pushes Docker images to Amazon ECR.

**Features:**
- Automatic ECR authentication
- Smart tagging (semantic, git-sha, latest)
- Repository creation
- Push verification

**Files:**
- `SKILL.md` - Skill definition
- `src/push_image.py` - Pusher logic

**Usage:**
```bash
python3 opencode/skills/ecr-image-pusher/src/push_image.py \
  --image fsdp:latest \
  --repository fsdp
```

### EKS Cluster Manager

Manages and validates Amazon EKS clusters.

**Features:**
- Cluster discovery
- GPU operator validation
- EFA checks
- Auto-fix common issues

**Files:**
- `SKILL.md` - Skill definition
- `src/manage_cluster.py` - Manager logic

**Usage:**
```bash
python3 opencode/skills/eks-cluster-manager/src/manage_cluster.py \
  --cluster_name my-cluster \
  --auto_fix
```

### Training Job Deployer

Deploys distributed PyTorch training jobs on EKS.

**Features:**
- Automatic torchrun configuration
- PyTorchJob integration
- Multi-node support
- Real-time monitoring
- Auto-retry on failures

**Files:**
- `SKILL.md` - Skill definition
- `src/deploy_job.py` - Deployer logic

**Usage:**
```bash
python3 opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster \
  --num_nodes 4 \
  --job_name llama-training
```

## 📂 Directory Structure

```
opencode/skills/
├── docker-image-builder/
│   ├── SKILL.md              # OpenCode skill definition
│   ├── README.md             # Detailed documentation
│   ├── skill.yaml            # Legacy definition (for reference)
│   └── src/                  # Source code
│       ├── build_image.py
│       ├── conflict_analyzer.py
│       ├── base_image_selector.py
│       └── smoke_test.py
├── docker-image-tester/
│   ├── SKILL.md
│   ├── README.md
│   ├── skill.yaml
│   └── src/
│       └── test_image.py
├── ecr-image-pusher/
│   ├── SKILL.md
│   ├── README.md
│   ├── skill.yaml
│   └── src/
│       └── push_image.py
├── eks-cluster-manager/
│   ├── SKILL.md
│   └── src/
│       └── manage_cluster.py
├── training-job-deployer/
│   ├── SKILL.md
│   ├── skill.yaml
│   └── src/
│       └── deploy_job.py
├── shared/                   # Common utilities
│   ├── __init__.py
│   ├── aws_utils.py
│   ├── docker_utils.py
│   ├── k8s_utils.py
│   └── logger.py
├── infrastructure/           # AWS infrastructure
│   └── aws-cli/
│       └── setup-codebuild.sh
├── README.md                 # This file
└── IMPLEMENTATION_SUMMARY.md # Implementation details
```

## 🔧 Prerequisites

### For All Skills
- Python 3.8+
- AWS CLI configured: `aws configure`
- boto3: `pip install boto3`

### For Docker Skills
- Docker installed (for local builds)
- Or use CodeBuild (recommended)

### For EKS Skills
- kubectl installed
- EKS cluster access

## 🎯 Complete Workflow

Complete workflow from build to deployment:

```bash
# 1. Build Docker image
python3 opencode/skills/docker-image-builder/src/build_image.py \
  --dockerfile Dockerfile \
  --auto_fix true

# 2. Test the image
python3 opencode/skills/docker-image-tester/src/test_image.py \
  --image fsdp:latest \
  --level standard

# 3. Push to ECR
python3 opencode/skills/ecr-image-pusher/src/push_image.py \
  --image fsdp:latest \
  --repository fsdp

# 4. Validate EKS cluster
python3 opencode/skills/eks-cluster-manager/src/manage_cluster.py \
  --cluster_name my-cluster \
  --auto_fix

# 5. Deploy training job
python3 opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster \
  --num_nodes 4 \
  --job_name llama32-1b-training \
  --monitor
```

## 📝 SKILL.md Format

Each skill includes a `SKILL.md` file following OpenCode format:

```markdown
---
name: skill-name
description: Brief description of what the skill does
license: MIT
compatibility: opencode
metadata:
  category: build
  author: opencode
---

## What I do
Description of skill capabilities...

## When to use me
When to use this skill...

## How to use me
Usage examples...

## Parameters
- param1: Description
- param2: Description
```

## 🔍 Troubleshooting

### Skills Not Loading
1. Verify skills are in `~/.config/opencode/skills/`
2. Check that each skill has a `SKILL.md` file
3. Restart OpenCode

### Permission Errors
1. Ensure AWS credentials: `aws configure`
2. Check IAM permissions for ECR, EKS, CodeBuild
3. Verify kubectl: `kubectl get nodes`

### Build Failures
1. Check Docker is running (for local builds)
2. Review CloudWatch logs (for CodeBuild)
3. Verify base image exists

## 📚 Additional Documentation

- [Main README](../../README.md) - Project overview
- [USAGE.md](../../USAGE.md) - Complete usage guide
- [CODEBUILD_TEST_SESSION.md](../../CODEBUILD_TEST_SESSION.md) - CodeBuild testing
- [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) - Implementation details

## 🤝 Contributing

To add new skills:
1. Create directory: `opencode/skills/your-skill/`
2. Add `SKILL.md` with proper frontmatter
3. Add source code in `src/`
4. Add documentation in `README.md`
5. Update this README

## 📄 License

MIT License - See LICENSE file for details

---

**Built with ❤️ for the PyTorch FSDP community**
