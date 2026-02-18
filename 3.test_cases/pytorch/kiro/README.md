# Kiro IDE Skills for PyTorch FSDP Distributed Training

This directory contains [Kiro IDE](https://kiro.dev) skills, steering files, and hook recipes for deploying PyTorch FSDP distributed training on Amazon EKS.

Skills follow the open [Agent Skills](https://agentskills.io) standard and are compatible with Kiro, OpenCode, Claude Code, and Codex.

## Setup

Kiro auto-discovers skills from `.kiro/skills/` in your workspace. Since this directory is named `kiro/` (without the dot) for repo visibility, you need to symlink or copy it:

```bash
# From the pytorch/ directory:
ln -s kiro .kiro

# Or copy:
cp -r kiro .kiro
```

After this, Kiro will automatically discover all 7 skills and 2 steering files.

## What's Included

### Skills (`skills/`)

| Skill | Description |
|-------|-------------|
| `docker-image-builder` | Build Docker images with auto-detection (local Docker or CodeBuild fallback) |
| `docker-image-tester` | Test images with import validation, CUDA checks, and smoke tests |
| `ecr-image-pusher` | Push images to Amazon ECR with auto-tagging |
| `eks-cluster-manager` | Discover, validate, and manage EKS clusters for training |
| `pytorchjob-manager` | Create, monitor, get logs, and delete PyTorchJob resources |
| `training-job-deployer` | Orchestrate end-to-end deployment (torchrun, PyTorchJob, Ray) |
| `training-monitor` | Monitor jobs with auto-restart, GPU/EFA health checks |

Kiro loads skill descriptions at startup and activates the full instructions on demand when your request matches. No need to invoke them manually -- just describe what you want to do:

- *"Build the Docker image"* -- activates `docker-image-builder`
- *"Deploy training on 4 nodes"* -- activates `training-job-deployer`
- *"Check GPU utilization"* -- activates `training-monitor`

### Steering (`steering/`)

Steering files provide persistent context that Kiro includes in every interaction.

| File | Contents |
|------|----------|
| `tech.md` | PyTorch FSDP stack, GPU instances, environment variables, tokenizer config |
| `deployment.md` | CodeBuild-first pipeline, directory layout, AWS resources, known issues |

These are set to `inclusion: always`, so Kiro always knows about your tech stack and deployment architecture without you having to explain it each time.

### Hooks (`hooks/`)

Hook recipes for automating tasks in the Kiro IDE. Set these up through the Agent Hooks panel. See [`hooks/README.md`](hooks/README.md) for details.

Recommended hooks:
- **Dockerfile conflict analysis** -- on save, check for PyTorch/CUDA version mismatches
- **Training script validation** -- on save, verify distributed training compatibility
- **Requirements conflict check** -- on save, detect torch/torchvision conflicts
- **BuildSpec validation** -- on save, validate CodeBuild config

## Quick Start

1. **Setup**: Symlink this directory (see [Setup](#setup) above)

2. **Build an image**:
   > "Build the FSDP Docker image and push to ECR"

3. **Deploy training**:
   > "Deploy Llama 3.2 1B training on 4 GPU nodes"

4. **Monitor**:
   > "Check training health -- GPU utilization, EFA status, and checkpoint progress"

## Cross-Provider Compatibility

These skills work across multiple AI coding tools:

| Provider | Location | Auto-discovery |
|----------|----------|----------------|
| **Kiro** | `.kiro/skills/` (symlink from `kiro/`) | Yes |
| **OpenCode** | `opencode/skills/` | Yes (via `~/.config/opencode/skills/`) |
| **Claude Code** | Copy to `.claude/skills/` | Yes |
| **Codex (OpenAI)** | Copy to `.agents/skills/` | Yes |

The `SKILL.md` format is the same across all providers. Only the directory placement differs.

## Directory Structure

```
kiro/
├── README.md                  # This file
├── skills/
│   ├── docker-image-builder/
│   │   ├── SKILL.md           # Skill instructions (agentskills.io standard)
│   │   ├── skill.yaml         # Parameters and outputs
│   │   ├── scripts/build.sh   # Shell wrapper
│   │   └── src/               # Python implementation
│   ├── docker-image-tester/
│   ├── ecr-image-pusher/
│   ├── eks-cluster-manager/
│   ├── pytorchjob-manager/
│   ├── training-job-deployer/
│   └── training-monitor/
├── steering/
│   ├── tech.md                # Technology stack (always included)
│   └── deployment.md          # Deployment architecture (always included)
└── hooks/
    └── README.md              # Hook recipes for Kiro IDE
```
