# Kiro Hooks for PyTorch FSDP Training

Kiro hooks automate tasks when specific events occur. Set these up through the
Kiro IDE panel: **Agent Hooks** > **+** > configure trigger and instructions.

## Recommended Hooks

### 1. Dockerfile Conflict Analysis (File Save)

**Trigger**: File Save
**File pattern**: `**/Dockerfile`
**Instructions**:
```
Analyze the saved Dockerfile for potential issues:
1. Check if the base image PyTorch version is compatible with the CUDA version
2. Verify that pip install uses --no-cache-dir
3. Check if requirements.txt has torch/torchvision version conflicts
4. Report any issues found with suggested fixes
```

### 2. Training Script Validation (File Save)

**Trigger**: File Save
**File pattern**: `**/train.py`
**Instructions**:
```
Validate the training script for distributed training compatibility:
1. Verify it reads RANK, WORLD_SIZE, LOCAL_RANK from environment variables
2. Check that dist.init_process_group() is called correctly
3. Verify CUDA device assignment uses LOCAL_RANK
4. Check that model is wrapped with FSDP
5. Report any issues that would break PyTorchJob deployment
```

### 3. Requirements Conflict Check (File Save)

**Trigger**: File Save
**File pattern**: `**/requirements.txt`
**Instructions**:
```
Check requirements.txt for package conflicts:
1. Verify torch and torchvision versions are compatible
2. Check that transformers version supports the torch version
3. Flag any packages that conflict with the base Docker image
4. Suggest fixes for any conflicts found
```

### 4. BuildSpec Validation (File Save)

**Trigger**: File Save
**File pattern**: `**/buildspec.yml`
**Instructions**:
```
Validate the CodeBuild buildspec:
1. Check that all phases (pre_build, build, post_build) are present
2. Verify ECR login command is correct
3. Check that docker build and push commands use correct image tags
4. Validate environment variable references
```

### 5. Post-Build Documentation (Agent Stop)

**Trigger**: Agent Stop
**Instructions**:
```
If the agent just built a Docker image or deployed a training job,
summarize what was done including:
- Image name and tag
- Build method used (local Docker or CodeBuild)
- Any fixes applied
- Deployment status if applicable
```
