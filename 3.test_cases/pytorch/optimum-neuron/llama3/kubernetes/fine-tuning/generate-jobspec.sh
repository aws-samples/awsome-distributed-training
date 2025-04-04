#!/bin/bash

# AWS and Registry Configuration
export AWS_REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export REGISTRY=${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/
export IMAGE=peft-optimum-neuron
export TAG=:latest
export IMAGE_URI=${REGISTRY}${IMAGE}${TAG}

# Job Configuration
export NAMESPACE=kubeflow
export INSTANCE_TYPE=ml.trn1.32xlarge
export EFA_PER_NODE=8
export NEURON_PER_NODE=16

# Storage Configuration
export FSX_CLAIM=fsx-claim

# Model and Dataset Configuration
export MODEL_ID=NousResearch/Llama-3.2-1B
export MODEL_OUTPUT_PATH=/fsx/peft_ft/model_artifacts/llama3.2-1B
export TOKENIZER_OUTPUT_PATH=/fsx/peft_ft/tokenizer/llama3.2-1B
export DATASET_NAME=databricks/databricks-dolly-15k

# Training Configuration
export NEURON_CACHE_DIR=/fsx/neuron_cache
export CHECKPOINT_DIR=/fsx/peft_ft/model_checkpoints
export CHECKPOINT_DIR_COMPILE=/fsx/peft_ft/model_checkpoints/compile
export FINAL_MODEL_PATH=/fsx/peft_ft/model_checkpoints/final_model_output
export MAX_SEQ_LENGTH=1024
export EPOCHS=1
export LEARNING_RATE=2e-05
export TP_SIZE=1
export PP_SIZE=1
export TRAIN_BATCH_SIZE=1

# Generate the final yaml files from templates
for template in tokenize_data compile_peft launch_peft_train consolidation merge_lora; do
    cat ${template}.yaml-template | envsubst > ${template}.yaml
done

echo "Generated all YAML files successfully."