#!/bin/bash

export AWS_REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export REGISTRY=${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/
export IMAGE=smpv2
export TAG=:latest
export IMAGE_URI=${REGISTRY}${IMAGE}${TAG}

export JOB_NAME=smpv2-llama2
export NUM_NODES=8
export INSTANCE_TYPE=ml.g5.8xlarge
export GPU_PER_NODE=1
export EFA_PER_NODE=1
export FI_PROVIDER=efa

export CHECKPOINT_DIR=/workspace/checkpoints
export TRAINING_DIR=/workspace/data
export TEST_DIR=/workspace/data

export TRAIN_BATCH_SIZE=4
export HIDDEN_WIDTH=4096
export NUM_LAYERS=32
export NUM_HEADS=32
export LLAMA_INTERMEDIATE_SIZE=11008
export SHARD_DEGREE=8
export USE_SYNTHETIC_DATA=1
export USE_FP8=0

cat smpv2.yaml-template | envsubst > smpv2.yaml

