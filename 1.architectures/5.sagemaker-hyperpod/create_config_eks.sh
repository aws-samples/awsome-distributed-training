#!/usr/bin/env bash
#
# create_config.sh - Generate environment configuration for SageMaker HyperPod
#
# Usage: bash create_config.sh
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO"' ERR

# Function to get CloudFormation outputs
get_cfn_output() {
    local output_key=$1
    aws cloudformation describe-stacks \
        --stack-name $STACK_ID \
        --query "Stacks[0].Outputs[?OutputKey=='${output_key}'].OutputValue" \
        --region ${AWS_REGION} \
        --output text
}

# Function to set variables with defaults
set_default_var() {
    local var_name=$1
    local default_value=$2
    
    if [ -z "${!var_name:-}" ]; then
        echo "[WARNING] ${var_name} environment variable is not set, automatically set to ${default_value}."
        eval "${var_name}=${default_value}"
    fi
    echo "export ${var_name}=${!var_name}" >> env_vars
    echo "[INFO] ${var_name} = ${!var_name}"
}

# Check AWS CLI availability
if ! command -v aws &> /dev/null; then
    echo "[ERROR] AWS CLI is not installed or not in PATH"
    exit 1
fi

# Verify AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "[ERROR] AWS credentials not configured or invalid"
    exit 1
fi

set_default_var "STACK_ID" "hyperpod-eks-full-stack"

# Backup existing config if it exists
if [ -f env_vars ]; then
    mv env_vars env_vars.$(date +%Y%m%d_%H%M%S).bak
fi

# Clear env_vars file
> env_vars 

# Define AWS Region
if [ -z "${AWS_REGION:-}" ]; then
    echo "[WARNING] AWS_REGION environment variable is not set, automatically set depending on aws cli default region."
    AWS_REGION=$(aws configure get region)
fi
echo "export AWS_REGION=${AWS_REGION}" >> env_vars
echo "[INFO] AWS_REGION = ${AWS_REGION}"

# Retrieve EKS CLUSTER Name
if [ -z "${EKS_CLUSTER_NAME:-}" ]; then
    EKS_CLUSTER_NAME=$(get_cfn_output 'ClusterName')
fi

if [[ ! -z "${EKS_CLUSTER_NAME:-}" ]]; then
    echo "export EKS_CLUSTER_NAME=${EKS_CLUSTER_NAME}" >> env_vars
    echo "[INFO] EKS_CLUSTER_NAME = ${EKS_CLUSTER_NAME}"
else
    echo "[ERROR] failed to retrieve EKS_CLUSTER_NAME"
    exit 1
fi

# Retrieve EKS CLUSTER ARN
if [ -z "${EKS_CLUSTER_ARN:-}" ]; then
    EKS_CLUSTER_ARN=$(get_cfn_output 'ClusterArn')
    
    # If not in CFN, attempt to construct ARN
    if [ -z "${EKS_CLUSTER_ARN:-}" ] && [ ! -z "${EKS_CLUSTER_NAME:-}" ]; then
        AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
        if [ ! -z "${AWS_ACCOUNT:-}" ]; then
            EKS_CLUSTER_ARN="arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT}:cluster/${EKS_CLUSTER_NAME}"
        fi
    fi
fi

if [ ! -z "${EKS_CLUSTER_ARN:-}" ]; then
    echo "export EKS_CLUSTER_ARN=${EKS_CLUSTER_ARN}" >> env_vars
    echo "[INFO] EKS_CLUSTER_ARN = ${EKS_CLUSTER_ARN}"
else
    echo "[ERROR] failed to retrieve EKS_CLUSTER_ARN"
    exit 1
fi

# Retrieve S3 Bucket Name
BUCKET_NAME=$(get_cfn_output 'AmazonS3BucketName')
if [[ ! -z "${BUCKET_NAME:-}" ]]; then
    echo "export BUCKET_NAME=${BUCKET_NAME}" >> env_vars
    echo "[INFO] BUCKET_NAME = ${BUCKET_NAME}"
else
    echo "[ERROR] failed to retrieve BUCKET_NAME"
    exit 1
fi

# Retrieve SageMaker Execution Role
EXECUTION_ROLE=$(get_cfn_output 'AmazonSagemakerClusterExecutionRoleArn')
if [[ ! -z "${EXECUTION_ROLE:-}" ]]; then
    echo "export EXECUTION_ROLE=${EXECUTION_ROLE}" >> env_vars
    echo "[INFO] EXECUTION_ROLE = ${EXECUTION_ROLE}"
else
    echo "[ERROR] failed to retrieve EXECUTION_ROLE"
    exit 1
fi

# Retrieve VPC ID
if [ -z "${VPC_ID:-}" ]; then
    VPC_ID=$(get_cfn_output 'VPC')
fi

if [[ ! -z "${VPC_ID:-}" ]]; then
    echo "export VPC_ID=${VPC_ID}" >> env_vars
    echo "[INFO] VPC_ID = ${VPC_ID}"
else
    echo "[ERROR] failed to retrieve VPC ID"
    exit 1
fi

# Retrieve private subnet ID
if [ -z "${SUBNET_ID:-}" ]; then
    SUBNET_ID=$(get_cfn_output 'PrivateSubnet1')
fi

if [[ ! -z "${SUBNET_ID:-}" ]]; then
    echo "export SUBNET_ID=${SUBNET_ID}" >> env_vars
    echo "[INFO] SUBNET_ID = ${SUBNET_ID}"
else
    echo "[ERROR] failed to retrieve SUBNET ID"
    exit 1
fi

# Get Security Group
if [ -z "${SECURITY_GROUP:-}" ]; then
    SECURITY_GROUP=$(get_cfn_output 'NoIngressSecurityGroup')
fi

if [[ ! -z "${SECURITY_GROUP:-}" ]]; then
    echo "export SECURITY_GROUP=${SECURITY_GROUP}" >> env_vars
    echo "[INFO] SECURITY_GROUP = ${SECURITY_GROUP}"
else
    echo "[ERROR] failed to retrieve Security Group"
    exit 1
fi

# Set default HyperPod Cluster name
set_default_var "HP_CLUSTER_NAME" "ml-cluster"

# Accelerated compute configuration
set_default_var "ACCEL_INSTANCE_TYPE" "ml.g5.12xlarge"
set_default_var "ACCEL_COUNT" "2"
set_default_var "ACCEL_VOLUME_SIZE" "500"

# General purpose compute configuration
set_default_var "GEN_INSTANCE_TYPE" "ml.m5.2xlarge"
set_default_var "GEN_COUNT" "1"
set_default_var "GEN_VOLUME_SIZE" "500"

# Node recovery configuration
set_default_var "NODE_RECOVERY" "Automatic"

# Set network flag for Docker if in SageMaker Code Editor
if [ "${SAGEMAKER_APP_TYPE:-}" = "CodeEditor" ]; then 
    echo "export DOCKER_NETWORK=\"--network sagemaker\"" >> env_vars
fi 

# Persist the environment variables
if [ -f ~/.bashrc ]; then
    echo "[ -f $(pwd)/env_vars ] && source $(pwd)/env_vars" >> ~/.bashrc
    echo "[INFO] Added environment variables to ~/.bashrc"
elif [ -f ~/.zshrc ]; then
    echo "[ -f $(pwd)/env_vars ] && source $(pwd)/env_vars" >> ~/.zshrc
    echo "[INFO] Added environment variables to ~/.zshrc"
fi

echo "[INFO] Configuration complete. Run 'source env_vars' to load variables in current shell."
