# OpenCode Skills for Distributed PyTorch Training

A comprehensive suite of skills for building, testing, and deploying distributed PyTorch training workloads on Amazon EKS (including HyperPod EKS) using OpenCode.

## Cross-Provider Compatibility

These skills follow the open [Agent Skills](https://agentskills.io) standard and work across multiple AI coding tools:

| Provider | Location | Auto-discovery | Setup |
|----------|----------|----------------|-------|
| **OpenCode** | `opencode/skills/` | Yes (via `~/.config/opencode/skills/`) | Copy to `~/.config/opencode/skills/` |
| **Kiro** | `kiro/skills/` | Yes (via `.kiro/skills/`) | Symlink `kiro/` to `.kiro/` |
| **Claude Code** | Copy to `.claude/skills/` | Yes | `cp -r opencode/skills/* .claude/skills/` |
| **Codex (OpenAI)** | Copy to `.agents/skills/` | Yes | `cp -r opencode/skills/* .agents/skills/` |

The `SKILL.md` format is identical across all providers -- only the directory placement differs.

## Available Skills

### Build & Deploy Pipeline
| Skill | Purpose | Location |
|-------|---------|----------|
| **docker-image-builder** | Build Docker images with auto-fix | `docker-image-builder/` |
| **docker-image-tester** | Test Docker images | `docker-image-tester/` |
| **ecr-image-pusher** | Push images to ECR | `ecr-image-pusher/` |
| **eks-cluster-manager** | Manage EKS clusters | `eks-cluster-manager/` |

### Training Deployment (Modular Architecture)

The training deployment is split into a thin orchestrator + 6 focused sub-skills:

| Skill | Purpose | Location |
|-------|---------|----------|
| **training-job-deployer** | Orchestrator - delegates to sub-skills below | `training-job-deployer/` |
| **k8s_cluster_manager** | Cluster health, GPU/EFA validation | `k8s_cluster_manager/` |
| **ray-cluster-manager** | Ray/KubeRay lifecycle and YAML generation | `ray-cluster-manager/` |
| **pytorchjob-manager** | Kubeflow PyTorchJob management | `pytorchjob-manager/` |
| **checkpoint-manager** | Storage, PVC setup, checkpoint discovery | `checkpoint-manager/` |
| **training-monitor** | GPU utilization, EFA, health reporting | `training-monitor/` |
| **hyperpod-manager** | HyperPod node discovery, labels, AMP | `hyperpod-manager/` |

## Quick Start

### Installation

Copy skills to your OpenCode skills directory:

```bash
# Create skills directory
mkdir -p ~/.config/opencode/skills

# Copy all skills from this repo
cp -r /path/to/repo/opencode/skills/* ~/.config/opencode/skills/

# Or copy specific skills (e.g., just the training sub-skills)
cp -r opencode/skills/training-job-deployer ~/.config/opencode/skills/
cp -r opencode/skills/k8s_cluster_manager ~/.config/opencode/skills/
cp -r opencode/skills/ray-cluster-manager ~/.config/opencode/skills/
cp -r opencode/skills/pytorchjob-manager ~/.config/opencode/skills/
cp -r opencode/skills/checkpoint-manager ~/.config/opencode/skills/
cp -r opencode/skills/training-monitor ~/.config/opencode/skills/
cp -r opencode/skills/hyperpod-manager ~/.config/opencode/skills/
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

## Skill Details

### Docker Image Builder

Builds Docker images with automatic conflict detection and resolution.

**Features:**
- PyTorch/CUDA compatibility analysis
- Auto-fix dependency conflicts
- Smart base image selection
- Retry logic (up to 3 attempts)

### Docker Image Tester

Comprehensive Docker image testing framework.

**Features:**
- Multiple test levels (quick, standard, full)
- Import validation
- CUDA availability checks
- Model configuration tests
- Forward pass validation

### ECR Image Pusher

Pushes Docker images to Amazon ECR.

**Features:**
- Automatic ECR authentication
- Smart tagging (semantic, git-sha, latest)
- Repository creation
- Push verification

### EKS Cluster Manager

Manages and validates Amazon EKS clusters.

**Features:**
- Cluster discovery
- GPU operator validation
- EFA checks
- Auto-fix common issues

### Training Job Deployer (Orchestrator)

Thin orchestrator that delegates to the 6 sub-skills below. Provides a single entry point for deploying distributed training jobs.

**Flow:**
1. Validate cluster (k8s_cluster_manager)
2. Setup storage (checkpoint-manager)
3. Deploy Ray cluster (ray-cluster-manager + hyperpod-manager)
4. Start training via `kubectl exec` on Ray head pod
5. Monitor training (training-monitor)

### k8s_cluster_manager (Sub-Skill)

Kubernetes cluster health and readiness validation.

**Key Functions:** `check_gpu_operator()`, `check_efa_plugin()`, `get_cluster_capacity()`, `check_kubeflow_operator()`

**Learnings Baked In:**
- Correct HyperPod label selectors (`sagemaker.amazonaws.com/compute-type`)
- Correct device plugin labels (`app.kubernetes.io/name=nvidia-device-plugin`)
- CPU millicore and memory unit parsing

### ray-cluster-manager (Sub-Skill)

Ray/KubeRay cluster lifecycle management.

**Key Functions:** `generate_raycluster_yaml()`, `get_ray_status()`, `verify_gpu_utilization()`, `get_ray_job_command()`

**Learnings Baked In:**
- EFA environment variables in RayCluster YAML
- Do NOT use `ray job submit` for multi-GPU training

### pytorchjob-manager (Sub-Skill)

Kubeflow PyTorchJob creation and management.

**Key Functions:** `create_pytorchjob()`, `get_job_status()`, `stream_logs()`

**Learnings Baked In:**
- Correct log label: `training.kubeflow.org/job-name`
- `num_workers=1` edge case handling

### checkpoint-manager (Sub-Skill)

Persistent storage and checkpoint management.

**Key Functions:** `create_checkpoint_pvc()`, `find_latest_checkpoint_on_pod()`, `list_checkpoints_on_pod()`

**Learnings Baked In:**
- Remote checkpoint discovery via `kubectl exec`
- Shared PVC across Ray head + workers

### training-monitor (Sub-Skill)

Combined health monitoring for running training jobs.

**Key Functions:** `get_training_health()`, `print_training_health()`, `check_gpu_utilization()`, `check_efa_utilization()`, `verify_ray_resources()`

**Features:**
- Single-call health report combining GPU, EFA, checkpoints, Ray resources
- Pretty-printed output for quick diagnosis

### hyperpod-manager (Sub-Skill)

HyperPod-specific node discovery and management.

**Key Functions:** `get_hyperpod_nodes()`, `get_instance_type()`, `query_amp()`

**Learnings Baked In:**
- Correct HyperPod label selectors
- Region parameter for AMP API calls

## Directory Structure

```
opencode/skills/
├── docker-image-builder/        # Build pipeline
│   ├── SKILL.md
│   └── src/
├── docker-image-tester/         # Test pipeline
│   ├── SKILL.md
│   └── src/
├── ecr-image-pusher/            # Push pipeline
│   ├── SKILL.md
│   └── src/
├── eks-cluster-manager/         # EKS management
│   ├── SKILL.md
│   └── src/
├── training-job-deployer/       # Orchestrator (thin)
│   ├── SKILL.md
│   └── src/
│       └── deploy.py
├── k8s_cluster_manager/         # Sub-skill: cluster validation
│   ├── SKILL.md
│   └── src/
│       └── cluster_manager.py
├── ray-cluster-manager/         # Sub-skill: Ray/KubeRay
│   ├── SKILL.md
│   └── src/
│       └── ray_manager.py
├── pytorchjob-manager/          # Sub-skill: Kubeflow
│   ├── SKILL.md
│   └── src/
│       └── pytorchjob_manager.py
├── checkpoint-manager/          # Sub-skill: storage
│   ├── SKILL.md
│   └── src/
│       └── checkpoint_manager.py
├── training-monitor/            # Sub-skill: monitoring
│   ├── SKILL.md
│   └── src/
│       └── monitor.py
├── hyperpod-manager/            # Sub-skill: HyperPod
│   ├── SKILL.md
│   └── src/
│       └── hyperpod_manager.py
├── shared/                      # Legacy (deprecated - sub-skills are standalone)
│   ├── aws_utils.py
│   ├── k8s_utils.py
│   └── logger.py
├── infrastructure/              # AWS infrastructure setup
│   └── aws-cli/
│       └── setup-codebuild.sh
├── README.md                    # This file
└── IMPLEMENTATION_SUMMARY.md    # Full implementation details + learnings
```

## Prerequisites

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

## Complete Workflow

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

## SKILL.md Format

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

## Troubleshooting

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

## Additional Documentation

- [Main README](../../README.md) - Project overview
- [USAGE.md](../../USAGE.md) - Complete usage guide
- [CODEBUILD_TEST_SESSION.md](../../CODEBUILD_TEST_SESSION.md) - CodeBuild testing
- [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) - Implementation details

## Contributing

To add new skills:
1. Create directory: `opencode/skills/your-skill/`
2. Add `SKILL.md` with proper frontmatter
3. Add source code in `src/`
4. Each skill should be standalone (~100-200 lines, no `shared/` dependencies)
5. Use inline `logging.getLogger(__name__)` instead of importing from `logger.py`
6. Update this README with the new skill in the table

## License

MIT License - See LICENSE file for details

---

**Built for the distributed PyTorch training community**
