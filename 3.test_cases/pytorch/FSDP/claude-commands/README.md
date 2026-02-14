# Claude Code Commands for PyTorch FSDP

This directory contains Claude Code compatible commands for managing Docker images, EKS clusters, and training jobs for PyTorch FSDP workloads.

## Available Commands

### 1. build_docker_image
Build Docker images with automatic conflict detection and resolution.

```python
build_docker_image(
    dockerfile="Dockerfile",
    context=".",
    tag="auto",
    auto_fix=True,
    max_attempts=3
)
```

**Example:**
```python
# Build with defaults
build_docker_image()

# Build specific Dockerfile
build_docker_image(dockerfile="Dockerfile.gpu", tag="v1.0")

# Build without auto-fix
build_docker_image(auto_fix=False)
```

### 2. manage_eks_cluster
Discover, validate, and manage EKS clusters for training.

```python
manage_eks_cluster(
    cluster_name=None,  # Auto-discover if None
    region="us-west-2",
    validate_components=True,
    auto_fix=False,
    create_if_missing=False
)
```

**Example:**
```python
# Interactive cluster selection
manage_eks_cluster()

# Validate specific cluster
manage_eks_cluster(cluster_name="my-cluster", auto_fix=True)

# Create cluster if none exists
manage_eks_cluster(create_if_missing=True)
```

### 3. deploy_training_job
Deploy training jobs to EKS with monitoring and auto-retry.

```python
deploy_training_job(
    job_name="fsdp-training",
    image_uri=None,  # Auto-detect from ECR
    instance_type="ml.g5.8xlarge",
    num_nodes=8,
    cluster_name="my-cluster",
    monitor=True,
    auto_retry=True
)
```

**Example:**
```python
# Deploy with defaults
deploy_training_job(cluster_name="my-cluster")

# Deploy custom configuration
deploy_training_job(
    job_name="llama3-8b",
    num_nodes=4,
    instance_type="ml.g5.8xlarge",
    monitor=True
)
```

## Complete Workflow Example

```python
# 1. Build Docker image
build_docker_image(auto_fix=True)

# 2. Test the image
test_docker_image(level="standard")

# 3. Push to ECR
push_to_ecr(repository="fsdp", tags="semantic")

# 4. Setup EKS cluster
manage_eks_cluster(auto_fix=True)

# 5. Deploy training job
deploy_training_job(
    job_name="fsdp-llama3-8b",
    num_nodes=8,
    monitor=True,
    auto_retry=True
)
```

## Installation

These commands are automatically available when using Claude Code in a project that includes this directory.

## Dependencies

- Python 3.8+
- AWS CLI
- Docker
- kubectl
- boto3

## Configuration

Set environment variables:

```bash
export AWS_REGION=us-west-2
export AWS_PROFILE=default
export ECR_REPOSITORY=fsdp
```

## Troubleshooting

### Command not found
Make sure the `claude-commands` directory is in your project root and Claude Code has indexed it.

### AWS credentials error
Run `aws configure` to set up your AWS credentials.

### Docker not found
Ensure Docker is installed and running: `docker --version`

### kubectl not found
Install kubectl: https://kubernetes.io/docs/tasks/tools/
