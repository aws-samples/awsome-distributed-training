# Amazon SageMaker Studio Integration with Amazon SageMaker HyperPod SLURM Cluster

This project provides automated setup and configuration for integrating Amazon SageMaker Studio with SLURM (Simple Linux Utility for Resource Management) on Amazon SageMaker HyperPod clusters. It enables seamless distributed training management through SLURM within the familiar Amazon SageMaker Studio environment (via JupyterLab or CodeEditor).

The solution automates the process of setting up the SLURM client configuration, authentication, and connectivity between SageMaker Studio and HyperPod clusters. It handles installation of required dependencies, SLURM client software compilation, security configuration including MUNGE authentication, and proper directory/permission setup. This allows data scientists to leverage SLURM's powerful distributed training capabilities directly from their familiar SageMaker Studio environment.

## Repository Structure
```
.
└── 1.architectures/
    └── 5.sagemaker-hyperpod/
        └── slurm-studio/
            ├── slurm_lifecycle.sh    # Automated script for SLURM environment setup on SageMaker Studio
            └── studio-slurm.yaml     # CloudFormation template for SageMaker Studio Domain setup
```

## Usage Instructions
### Prerequisites

- An AWS account with appropriate permissions
- Existing VPC with required subnets (same VPC as your SMHP cluster)
- Existing FSx Lustre file system (same FSxL as your SMHP cluster)
- Existing SageMaker HyperPod Slurm cluster
- Security group that allows communication with the HyperPod Slurm controller node (Same Security group as your SMHP cluster nodes)

### Installation

1. Deploy the CloudFormation template:
```bash
aws cloudformation create-stack \
  --stack-name sagemaker-studio-slurm \
  --template-body file://studio-slurm.yaml \
  --parameters \
    ParameterKey=ExistingVpcId,ParameterValue=<your-vpc-id> \
    ParameterKey=ExistingSubnetIds,ParameterValue=<your-subnet-ids> \
    ParameterKey=ExistingFSxLustreId,ParameterValue=<your-fsx-id> \
    ParameterKey=SecurityGroupId,ParameterValue=<your-security-group-id> \
    ParameterKey=HyperPodClusterName,ParameterValue=<your-smhp-cluster-name> \
    ParameterKey=HeadNodeName,ParameterValue=<your-controller-machine-name>
```

### Quick Start

1. After the CloudFormation stack deployment completes, open SageMaker Studio
2. The SLURM environment setup will begin automatically through lifecycle configurations
3. Monitor the setup progress (you can find the specific file in your CloudWatch logs under /aws/sagemaker/studio/<domain-id>/):
```bash
tail -f /tmp/slurm_lifecycle_*.log
```

### More Detailed Examples

Submitting a SLURM job from SageMaker Studio:
```bash
# Check SLURM cluster status
sinfo

# Submit a basic job
sbatch <<EOF
#!/bin/bash
#SBATCH --job-name=test
#SBATCH --output=/fsx/<>/test-%j.out
#SBATCH --error=/fsx/<>/test-%j.err
#SBATCH --nodes=1

srun echo "Hello World!"
EOF
```

### Troubleshooting

Common issues and solutions:

1. SLURM Authentication Failures
- Problem: "slurm_auth_info: authentication plugin munge not found"
- Solution: 
```bash
# Check MUNGE key permissions
ls -l /etc/munge/munge.key
# Should show: -r-------- 1 munge munge

# Restart MUNGE service
sudo systemctl restart munge
```

2. SLURM Protocol authentication error
- Problem: "slurm_load_partitions: Protocol authentication error"
- Solution:
The solution should be at the end of `tail -f /tmp/slurm_lifecycle_*.log`