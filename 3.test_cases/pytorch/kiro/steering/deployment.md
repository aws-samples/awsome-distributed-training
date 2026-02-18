---
inclusion: always
---

# Deployment Architecture

## Build Pipeline (CodeBuild-first)
1. **Build**: AWS CodeBuild builds Docker images (~$0.10/build, ~20-25 min)
   - Alternative: local Docker if available (auto-detected)
2. **Test**: Import validation, CUDA checks, smoke tests
3. **Push**: Tag and push to Amazon ECR
4. **Deploy**: PyTorchJob on EKS with torchrun

## Docker Image Build
- Use `python3 opencode/skills/docker-image-builder/src/build_image.py`
- Auto-detects local Docker or falls back to CodeBuild
- Includes conflict analysis (PyTorch/CUDA version mismatches) and auto-fix
- Runs smoke tests (import validation) before pushing

## Training Job Deployment
- Uses **PyTorchJob** CRD via Kubeflow Training Operator
- torchrun handles distributed process launch
- Master pod + N-1 Worker pods (e.g., 4 nodes = 1 Master + 3 Workers)
- Checkpoints saved to PVC at `/checkpoints/`

## Directory Layout
```
pytorch/
  .kiro/                    # Kiro skills and steering (this directory)
  opencode/skills/          # OpenCode skills (canonical source)
  claude-commands/           # Claude Code command wrappers
  FSDP/                     # Training code
    Dockerfile              # Training image
    buildspec.yml           # CodeBuild config
    src/train.py            # Training script
    src/requirements.txt    # torch==2.7.1, transformers==4.53.0
```

## AWS Resources (Reference)
- **Region**: us-west-2
- **ECR**: `<account>.dkr.ecr.us-west-2.amazonaws.com/fsdp`
- **CodeBuild project**: `pytorch-fsdp`
- **S3 bucket**: `pytorch-fsdp-build-artifacts-<account>`

## Known Issues
- torchrun path is `/opt/conda/bin/torchrun` (not in default PATH)
- EFA can silently fall back to TCP sockets -- verify with NCCL logs
- `ray job submit` isolates GPU access -- use `kubectl exec` instead
- Use public tokenizer `hf-internal-testing/llama-tokenizer` to avoid gated model auth
