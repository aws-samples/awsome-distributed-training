# Amazon SageMaker Hyperpod Cluster Automation Script

This project provides a script to automate the creation and setup of a Amazon SageMaker Hyperpod cluster with EKS integration.

The automation script streamlines the process of setting up a distributed training environment using AWS SageMaker Hyperpod.
It handles the installation and configuration of necessary tools, clones the required repository, sets up environment variables, and configures lifecycle scripts for the SageMaker Hyperpod architecture.

## Demo

![SageMaker Hyperpod Cluster Automation Demo](/1.architectures/7.sagemaker-hyperpod-eks/automate-smhp-eks/media/automate-smhp-eks-demo.gif)

This demo gif showcases the step-by-step process of creating and setting up a SageMaker Hyperpod cluster using our automation script.

- `automate-eks-cluster-creation.sh`: The main script that automates the cluster creation process.
- `README.md`: This file, providing information about the project.

## Usage Instructions

### Prerequisites

- AWS CLI (version 2.17.47 or higher)
- Git
- Bash shell environment
- AWS account with appropriate permissions

### Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/aws-samples/awsome-distributed-training.git
   cd 1.architectures/7.sagemaker-hyperpod-eks/automate-smhp-eks
   ```

2. Make the script executable:
   ```bash
   chmod +x automate-eks-cluster-creation.sh
   ```

### Running the Script

Execute the script:

```bash
./automate-eks-cluster-creation.sh
```

The script will guide you through the following steps:

1. Check and install/update AWS CLI if necessary.
2. Verify Git installation, and install additional K8s packages (if not installed)
3. Clone the "awsome-distributed-training" repository.
4. Set up environment variables.
5. Configure lifecycle scripts for SageMaker Hyperpod.
6. Configure your EKS cluster
7. Add ADMIN users to your EKS cluster
8. Configure your SMHP cluster

### Configuration

During execution, you'll be prompted to provide the following information:

- Name of the SageMaker VPC CloudFormation stack (default: sagemaker-hyperpod)
- Instance group configuration (group name, instance type, instance count, etc)

### Troubleshooting

- If you encounter permission issues when attaching IAM policies, the script will provide options to:
  1. Run `aws configure` as an admin user within the script.
  2. Exit the script to run `aws configure` manually.
  3. Continue without configuring this step.

- If environment variable generation fails:
  1. You can choose to continue with the rest of the script (not recommended unless you know how to set the variables manually).
  2. Exit the script to troubleshoot the issue.

## Data Flow

The automation script follows this general flow:

1. Check and setup prerequisites (AWS CLI, Git, kubectl, helm, eksctl)
2. Clone necessary repositories 
3. Set up environment variables
4. Configure lifecycle scripts
5. Configure EKS cluster
6. Add EKS ADMIN users
7. SMHP Cluster Configuration
8. Create cluster

```
[Prerequisites] -> [Clone Repos] -> [Setup Env Vars] -> [Configure LCS] -> [Configure EKS Cluster] -> [Add EKS ADMIN users] -> [Create Cluster configuration] -> [Create cluster]
```

Important technical considerations:
- Ensure you have the necessary AWS permissions before running the script.
- IAM policy attachment requires admin permissions.
