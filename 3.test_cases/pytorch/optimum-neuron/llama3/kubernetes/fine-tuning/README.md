## PEFT fine tuning of Llama 3 on Amazon EKS with AWS Trainium
This README demonstrates how to perform efficient supervised fine tuning for a Meta Llama 3.1 model using Parameter-Efficient Fine Tuning (PEFT) on AWS Trainium with EKS. We use HuggingFace's Optimum-Neuron SDK to apply Low-Rank Adaptation (LoRA) to fine-tuning jobs, and use Trainiums to perform distributed training.

### Solution overview
This solution uses the following components:

### Distributed training infrastructure
AWS Trainium chips for deep learning acceleration
Hugging Face Optimum-Neuron for integrating Trainium with existing models and tools
LoRA for parameter-efficient fine tuning

## 0. Prerequisites

### 0.1. EKS Cluster 
Before running this training, you'll need to create an Amazon EKS or a SageMaker HyperPod EKS cluster with at least 1 trn1.32xlarge/ trn1n.32xlarge. Instructions can be found in [1.architectures](../../1.architectures), the [aws-do-eks](https://bit.ly/do-eks) project, or the [eks-blueprints](https://github.com/aws-ia/terraform-aws-eks-blueprints) project.

### 0.2 Setup Persistant Volume Claim(PVC) for fsx 

We need to setup an PVC for FSx to store the tokenized data and training checkpoints. Please follow the link [here](https://catalog.workshops.aws/sagemaker-hyperpod-eks/en-US/01-cluster/06-fsx-for-lustre) to setup FSx CSI Driver and PVC. 


## 1. Setting up environment


### Pull the pytorch-training-neuronx image locally

Login to ECR and pull the `pytorch-training-neuronx` image

```sh
region=us-east-1
dlc_account_id=763104351884
aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $dlc_account_id.dkr.ecr.$region.amazonaws.com

docker pull ${dlc_account_id}.dkr.ecr.${region}.amazonaws.com/huggingface-pytorch-training-neuronx:2.1.2-transformers4.43.2-neuronx-py310-sdk2.20.0-ubuntu20.04-v1.0
```

### Build Docker Image and push to ECR

We will build docker image using the [Dockerfile](Dockerfile) in this directory.  

```sh
export AWS_REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export REGISTRY=${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/
export IMAGE=peft-optimum-neuron
export TAG=:latest
docker build -t ${REGISTRY}${IMAGE}${TAG} .
```

Then push the image to your private registry

```sh
# Create registry if needed
export REGISTRY_COUNT=$(aws ecr describe-repositories | grep \"${IMAGE}\" | wc -l)
if [ "${REGISTRY_COUNT//[!0-9]/}" == "0" ]; then
    echo "Creating repository ${REGISTRY}${IMAGE} ..."
    aws ecr create-repository --repository-name ${IMAGE}
else
    echo "Repository ${REGISTRY}${IMAGE} already exists"
fi

# Login to registry
echo "Logging in to $REGISTRY ..."
aws ecr get-login-password | docker login --username AWS --password-stdin $REGISTRY

# Push image to registry
docker image push ${REGISTRY}${IMAGE}${TAG}
```

## Generate Job Spec Files for tokenization and training

The default config in the script launches a 8B Llama 3 model. When you run the generate-jobspec.sh script it creates 2 yaml files tokenize_data.yaml and llama3_train.yaml

Please edit the `./generate-jobspec.sh` script with your desired environment settings.

```bash
./generate-jobspec.sh
```

## Tokenize Data

```bash
kubectl apply -f ./tokenize_data.yaml
```
The tokenization process converts text data into a numerical format that the model can understand. This step uses HuggingFace's AutoTokenizer to load the model's tokenizer and process the databricks-dolly-15k dataset. The tokenizer handles:
- Breaking down input text into tokens based on vocabulary
- Converting tokens to numerical IDs
- Managing special tokens for sequence boundaries
- Handling padding tokens for consistent batch lengths

The process ensures proper sequence length management to balance between preserving context and staying within model limitations.


## Compile the model

```bash
kubectl apply -f ./compile_peft.yaml
```
Training on Trainium requires model compilation using the neuron_parallel_compile utility. This step:
- Extracts computation graphs from a trial run (~10 training steps)
- Performs parallel pre-compilation of these graphs
- Uses identical scripts to actual training but with reduced max_steps
- Prepares the model for efficient execution on Trainium hardware

The compilation process is essential for optimizing model performance on the specialized Trainium architecture.


## Train Model

```bash
kubectl apply -f ./launch_peft_train.yaml
```
The training process uses tensor parallelism with degree 8 and leverages all 32 NeuronCores in the ml.trn1.32xlarge instance. Key features include:
- Data parallel degree of 4
- BFloat16 precision (XLA_USE_BF16=1) for reduced memory footprint
- Gradient accumulation steps of 3 for larger effective batch size
- LoRA configuration with:
  - r=16 (rank)
  - lora_alpha=16
  - lora_dropout=0.05
  - Target modules: q_proj and v_proj


## Consolidation the trained weights

```bash
kubectl apply -f ./consolidation.yaml
```
During distributed training, model checkpoints are split across multiple devices. The consolidation process:
- Combines distributed checkpoints into a unified model
- Processes tensors in memory-efficient chunks
- Creates sharded outputs with an index file
- Saves the consolidated weights in safetensor format

This step is crucial for bringing together the distributed training results into a usable format.


# Merge LoRA weights

```bash
kubectl apply -f ./merge_lora.yaml
```
The final step merges the LoRA adapters with the base model. This process:
- Loads the base model and LoRA configuration
- Transforms LoRA weight names to match base model structure
- Merges the adapters with the original model weights
- Saves the final model in a sharded format

The resulting merged model combines the base model's knowledge with the task-specific adaptations learned during fine-tuning, while maintaining the efficiency benefits of LoRA training.
