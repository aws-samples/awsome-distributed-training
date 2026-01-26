#!/bin/bash

# Simple script to copy container images to ECR
# Usage: ./simple-copy-images-to-ecr.sh AWS_REGION AWS_ACCOUNT_ID

# Set variables
REGION=$1
ACCOUNT_ID=$2

# Login to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Note: No need to login to AWS ECR registries for skipped images
# NVIDIA Container Registry (nvcr.io) allows anonymous access for public images

# AWS EFA Device Plugin - SKIPPED
# This image is available in all AWS regions, no need to copy to private ECR
# Will use: 602401143452.dkr.ecr.$REGION.amazonaws.com/eks/aws-efa-k8s-device-plugin:v0.5.6
echo "Skipping aws-efa-k8s-device-plugin (available in all regions)..."

# HyperPod Health Monitoring Agent - SKIPPED
# This image is available in all AWS regions with region-specific account IDs
# Will use regional AWS ECR: {account_id}.dkr.ecr.$REGION.amazonaws.com/hyperpod-health-monitoring-agent:1.0.819.0_1.0.267.0
echo "Skipping hyperpod-health-monitoring-agent (available in all regions with regional account IDs)..."

# NVIDIA Device Plugin
echo "Processing nvidia-k8s-device-plugin..."
SOURCE_IMAGE="nvcr.io/nvidia/k8s-device-plugin:v0.16.1"
TARGET_REPO="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/nvidia-k8s-device-plugin"

aws ecr create-repository --repository-name nvidia-k8s-device-plugin --region $REGION
docker pull --platform linux/amd64 $SOURCE_IMAGE
docker tag $SOURCE_IMAGE $TARGET_REPO:latest
docker tag $SOURCE_IMAGE $TARGET_REPO:v0.16.1
docker push $TARGET_REPO:latest
docker push $TARGET_REPO:v0.16.1

# MPI Operator
echo "Processing mpi-operator..."
SOURCE_IMAGE="mpioperator/mpi-operator:0.5"
TARGET_REPO="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/mpi-operator"

aws ecr create-repository --repository-name mpi-operator --region $REGION
docker pull --platform linux/amd64 $SOURCE_IMAGE
docker tag $SOURCE_IMAGE $TARGET_REPO:latest
docker tag $SOURCE_IMAGE $TARGET_REPO:0.5
docker push $TARGET_REPO:latest
docker push $TARGET_REPO:0.5

# Kubeflow Training Operator
echo "Processing kubeflow-training-operator..."
SOURCE_IMAGE="kubeflow/training-operator:v1-855e096"
TARGET_REPO="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/kubeflow-training-operator"

aws ecr create-repository --repository-name kubeflow-training-operator --region $REGION
docker pull --platform linux/amd64 $SOURCE_IMAGE
docker tag $SOURCE_IMAGE $TARGET_REPO:latest
docker tag $SOURCE_IMAGE $TARGET_REPO:v1-855e096
docker push $TARGET_REPO:latest
docker push $TARGET_REPO:v1-855e096

echo "All images copied to ECR successfully!"