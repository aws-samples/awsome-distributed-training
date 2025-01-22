# Running Megatron-LM on Kubernetes

This directory contains Kubernetes-specific instructions and templates for setting up and running MegatronLM on an EKS cluster.

## 1. Preparation

Ensure you have the following prerequisites:

- A functional EKS cluster on AWS.
- Docker installed for building the container image.
- An FSx for Lustre filesystem mounted on `/fsx` in all nodes or a persistent volume claim that can be mounted on `/fsx` in pods running on EKS. An example of setting up FSx on EKS is available [here](https://github.com/aws-samples/aws-do-eks/tree/main/Container-Root/eks/deployment/csi/fsx).

Set up the following environment variables in your terminal:

```bash
export DATA_PATH=/fsx # FSx for Lustre shared file-system
```


### 2. Building the Container

1. Copy the megatron-lm.Dockerfile to your local machine.

2. Build the containerimage:

```bash
docker build -t megatron-training -f megatron-lm.Dockerfile .
```

3. Tag and push the image to your container registry:

```bash
export AWS_REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export REGISTRY=${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/
docker tag megatron-training:latest ${REGISTRY}megatron-training:latest
docker push ${REGISTRY}megatron-training:latest
```

Now you are all set for distributed training with Megatron-LM on EKS! Proceed to the subdirectories for detailed instructions for different model training.