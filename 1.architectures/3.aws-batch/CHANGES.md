# Simplification Changes

## Summary
Simplified the AWS Batch distributed training setup by removing dependencies and consolidating the deployment into a single CloudFormation template with inline scripts.

## Key Changes

### 1. Removed jq Dependency
- **bootstrap.sh**: Removed all JSON parsing logic that required `jq`
- Now uses simple text-based secret format (plain private key)
- Region detection simplified using `grep` and `cut` instead of `jq`

### 2. EC2 Key Pair Generation
- **CloudFormation**: Added `AWS::EC2::KeyPair` resource that generates SSH key pair during stack deployment
- Private key automatically stored in Secrets Manager using `!GetAtt BatchSSHKeyPair.PrivateKeyValue`
- No manual key generation or upload required

### 3. Simplified Container Setup
- **Removed**: Custom Dockerfile (`nccl-tests-Batch-MNP.Dockerfile`) is no longer needed
- **Removed**: Separate bootstrap.sh script copied into container
- **Added**: Inline bash script in CloudFormation Job Definition `Command` section
- Container now uses base `public.ecr.aws/hpc-cloud/nccl-tests:latest` image directly

### 4. Inline Hostfile Setup Script
The Job Definition now contains a complete inline script that:
- Installs required packages (openssh, awscli) at runtime
- Generates SSH host keys
- Fetches private key from Secrets Manager
- Sets up SSH authentication
- Handles node registration (workers → main)
- Builds MPI hostfile on main node
- Launches NCCL test with mpirun

## Benefits
- **Simpler deployment**: No need to build and push custom Docker images
- **Fewer dependencies**: Removed jq requirement
- **Automated key management**: EC2 key pair generated automatically during CloudFormation deployment
- **Single source of truth**: All configuration in one CloudFormation template
- **Easier maintenance**: No separate Dockerfile or bootstrap script to maintain

## Usage
1. Deploy CloudFormation stack: `aws-batch-distributed-training-p6.yaml`
2. Stack automatically generates SSH key pair and stores in Secrets Manager
3. Submit Batch job - containers will fetch keys and setup SSH at runtime
4. No custom image building required

## Files Modified
- `scripts/bootstrap.sh` - Simplified, removed jq dependency (kept for reference)
- `aws-batch-distributed-training-p6.yaml` - Added key pair generation, inline container script
- `nccl-tests-Batch-MNP.Dockerfile` - No longer needed (can be removed)

## Migration Notes
If upgrading from previous version:
- Delete old SSH keys from Secrets Manager (will be replaced by auto-generated key)
- No need to build/push custom Docker images anymore
- Update any job submission scripts to use new Job Definition
