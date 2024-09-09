#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

: "${STACK_ID:=hyperpod-eks-full-stack}"

# Clear previously set env_vars 
> env_vars 

# Define AWS Region
if [ -z ${AWS_REGION} ]; then
    echo "[WARNING] AWS_REGION environment variable is not set, automatically set depending on aws cli default region."
    export AWS_REGION=$(aws configure get region)
fi
echo "export AWS_REGION=${AWS_REGION}" >> env_vars
echo "[INFO] AWS_REGION = ${AWS_REGION}"

# Retrieve EKS CLUSTER Name if not already defined
if [ "$EKS_CLUSTER_NAME" == "" ]; then
    export EKS_CLUSTER_NAME=`aws cloudformation describe-stacks \
        --stack-name $STACK_ID \
        --query 'Stacks[0].Outputs[?OutputKey==\`ClusterName\`].OutputValue' \
        --region ${AWS_REGION} \
        --output text`
fi

if [[ ! -z $EKS_CLUSTER_NAME ]]; then
    echo "export EKS_CLUSTER_NAME=${EKS_CLUSTER_NAME}" >> env_vars
    echo "[INFO] EKS_CLUSTER_NAME = ${EKS_CLUSTER_NAME}"
else
    echo "[ERROR] failed to retrieve EKS_CLUSTER_NAME"
    return 1
fi

# Retrieve EKS CLUSTER ARN
# check if already set 
if [ "$EKS_CLUSTER_ARN" == "" ]; then
    # if not, attempt to retrieve from cfn 
    export EKS_CLUSTER_ARN=`aws cloudformation describe-stacks \
        --stack-name $STACK_ID \
        --query 'Stacks[0].Outputs[?OutputKey==\`ClusterArn\`].OutputValue' \
        --region ${AWS_REGION} \
        --output text`
fi

# if not in cfn
if [ "$EKS_CLUSTER_ARN" == "" ]; then
    # check for cluster name
    if [ ! "$EKS_CLUSTER_NAME" == "" ]; then
        AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
        # check for account 
        if [ ! "$AWS_ACCOUNT" == "" ]; then
            # attempt to construct ARN
            export EKS_CLUSTER_ARN="arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT}:cluster/${EKS_CLUSTER_NAME}"
        fi
    fi
fi

# if previously set, or in cfn, or able to construct 
if [ ! "$EKS_CLUSTER_ARN" == "" ]; then
    echo "export EKS_CLUSTER_ARN=${EKS_CLUSTER_ARN}" >> env_vars
    echo "[INFO] EKS_CLUSTER_ARN = ${EKS_CLUSTER_ARN}"
else
    echo "[ERROR] failed to retrieve EKS_CLUSTER_ARN"
    return 1
fi

# Retrieve S3 Bucket Name 
export BUCKET_NAME=`aws cloudformation describe-stacks \
    --stack-name $STACK_ID \
    --query 'Stacks[0].Outputs[?OutputKey==\`AmazonS3BucketName\`].OutputValue' \
    --region ${AWS_REGION} \
    --output text`

if [[ ! -z $BUCKET_NAME ]]; then
    echo "export BUCKET_NAME=${BUCKET_NAME}" >> env_vars
    echo "[INFO] BUCKET_NAME = ${BUCKET_NAME}"
else
    echo "[ERROR] failed to retrieve BUCKET_NAME"
    return 1
fi

# Retrieve SageMaker Execution Role 
export EXECUTION_ROLE=`aws cloudformation describe-stacks \
    --stack-name $STACK_ID \
    --query 'Stacks[0].Outputs[?OutputKey==\`AmazonSagemakerClusterExecutionRoleArn\`].OutputValue' \
    --region ${AWS_REGION} \
    --output text`

if [[ ! -z $EXECUTION_ROLE ]]; then
    echo "export EXECUTION_ROLE=${EXECUTION_ROLE}" >> env_vars
    echo "[INFO] EXECUTION_ROLE = ${EXECUTION_ROLE}"
else
    echo "[ERROR] failed to retrieve EXECUTION_ROLE"
    return 1
fi

# Retrieve VPC ID
if [ "$VPC_ID" == "" ]; then
    export VPC_ID=`aws cloudformation describe-stacks \
        --stack-name $STACK_ID \
        --query 'Stacks[0].Outputs[?OutputKey==\`VPC\`].OutputValue' \
        --region ${AWS_REGION} \
        --output text`
fi

if [[ ! -z $VPC_ID ]]; then
    echo "export VPC_ID=${VPC_ID}" >> env_vars
    echo "[INFO] VPC_ID = ${VPC_ID}"
else
    echo "[ERROR] failed to retrieve VPC ID"
    return 1
fi

# Grab the private subnet id
if [ "$SUBNET_ID" == "" ]; then
    export SUBNET_ID=`aws cloudformation describe-stacks \
        --stack-name $STACK_ID \
        --query 'Stacks[0].Outputs[?OutputKey==\`PrivateSubnet1\`].OutputValue' \
        --region ${AWS_REGION} \
        --output text`
fi

if [[ ! -z $SUBNET_ID ]]; then
    echo "export SUBNET_ID=${SUBNET_ID}" >> env_vars
    echo "[INFO] SUBNET_ID = ${SUBNET_ID}"
else
    echo "[ERROR] failed to retrieve SUBNET ID"
    return 1
fi

# Grab the public ssubnet id
# export PUBLIC_SUBNET_ID=`aws cloudformation describe-stacks \
#     --stack-name $STACK_ID \
#     --query 'Stacks[0].Outputs[?OutputKey==\`PublicSubnet1\`].OutputValue' \
#     --region ${AWS_REGION} \
#     --output text`

# if [[ ! -z $PUBLIC_SUBNET_ID ]]; then
#     echo "export PUBLIC_SUBNET_ID=${PUBLIC_SUBNET_ID}" >> env_vars
#     echo "[INFO] PUBLIC_SUBNET_ID = ${PUBLIC_SUBNET_ID}"
# else
#     echo "[ERROR] failed to retrieve Public SUBNET ID"
#     return 1
# fi

# Get FSx Filesystem id from CloudFormation
# export FSX_ID=`aws cloudformation describe-stacks \
#     --stack-name $STACK_ID \
#     --query 'Stacks[0].Outputs[?OutputKey==\`FSxLustreFilesystemId\`].OutputValue' \
#     --region ${AWS_REGION} \
#     --output text`

# if [[ ! -z $FSX_ID ]]; then
#     echo "export FSX_ID=${FSX_ID}" >> env_vars
#     echo "[INFO] FSX_ID = ${FSX_ID}"
# else
#     echo "[ERROR] failed to retrieve FSX ID"
#     return 1
# fi

# Get FSx Filesystem Mountname from CloudFormation
# export FSX_MOUNTNAME=`aws cloudformation describe-stacks \
#     --stack-name $STACK_ID \
#     --query 'Stacks[0].Outputs[?OutputKey==\`FSxLustreFilesystemMountname\`].OutputValue' \
#     --region ${AWS_REGION} \
#     --output text`

# if [[ ! -z $FSX_MOUNTNAME ]]; then
#     echo "export FSX_MOUNTNAME=${FSX_MOUNTNAME}" >> env_vars
#     echo "[INFO] FSX_MOUNTNAME = ${FSX_MOUNTNAME}"
# else
#     echo "[ERROR] failed to retrieve FSX Mountname"
#     return 1
# fi

# Get Security Group from CloudFormation
if [ "$SECURITY_GROUP" == "" ]; then
    export SECURITY_GROUP=`aws cloudformation describe-stacks \
        --stack-name $STACK_ID \
        --query 'Stacks[0].Outputs[?OutputKey==\`NoIngressSecurityGroup\`].OutputValue' \
        --region ${AWS_REGION} \
        --output text`
fi

if [[ ! -z $SECURITY_GROUP ]]; then
    echo "export SECURITY_GROUP=${SECURITY_GROUP}" >> env_vars
    echo "[INFO] SECURITY_GROUP = ${SECURITY_GROUP}"
else
    echo "[ERROR] failed to retrieve FSX Security Group"
    return 1
fi

# Define accelerated compute instance type.
if [ -z ${ACCEL_INSTANCE_TYPE} ]; then
    echo "[WARNING] ACCEL_INSTANCE_TYPE environment variable is not set, automatically set to ml.g5.12xlarge."
    export ACCEL_INSTANCE_TYPE=ml.g5.12xlarge
fi
echo "export ACCEL_INSTANCE_TYPE=${ACCEL_INSTANCE_TYPE}" >> env_vars
echo "[INFO] ACCEL_INSTANCE_TYPE = ${ACCEL_INSTANCE_TYPE}"

# Set number of accelerated compute nodes to deploy 
if [ -z ${ACCEL_COUNT} ]; then
    echo "[WARNING] ACCEL_COUNT environment variable is not set, automatically set to 1."
    export ACCEL_COUNT=1
fi
echo "export ACCEL_COUNT=${ACCEL_COUNT}" >> env_vars
echo "[INFO] ACCEL_COUNT = ${ACCEL_COUNT}"

# Set the EBS Volume size for the accelerated compute nodes 
if [ -z ${ACCEL_VOLUME_SIZE} ]; then
    echo "[WARNING] ACCEL_VOLUME_SIZE environment variable is not set, automatically set to 500."
    export ACCEL_VOLUME_SIZE=500
fi
echo "export ACCEL_VOLUME_SIZE=${ACCEL_VOLUME_SIZE}" >> env_vars
echo "[INFO] ACCEL_VOLUME_SIZE = ${ACCEL_VOLUME_SIZE}"

# Define general purpose compute instance type.
if [ -z ${GEN_INSTANCE_TYPE} ]; then
    echo "[WARNING] GEN_INSTANCE_TYPE environment variable is not set, automatically set to ml.m5.2xlarge."
    export GEN_INSTANCE_TYPE=ml.m5.2xlarge
fi
echo "export GEN_INSTANCE_TYPE=${GEN_INSTANCE_TYPE}" >> env_vars
echo "[INFO] GEN_INSTANCE_TYPE = ${GEN_INSTANCE_TYPE}"

# Set the number of general purpose nodes to deploy
if [ -z ${GEN_COUNT} ]; then
    echo "[WARNING] GEN_COUNT environment variable is not set, automatically set to 1."
    export GEN_COUNT=1
fi
echo "export GEN_COUNT=${GEN_COUNT}" >> env_vars
echo "[INFO] GEN_COUNT = ${GEN_COUNT}"

# Set the EBS Volume size for the general purpose compute nodes 
if [ -z ${GEN_VOLUME_SIZE} ]; then
    echo "[WARNING] GEN_VOLUME_SIZE environment variable is not set, automatically set to 500."
    export GEN_VOLUME_SIZE=500
fi
echo "export GEN_VOLUME_SIZE=${GEN_VOLUME_SIZE}" >> env_vars
echo "[INFO] GEN_VOLUME_SIZE = ${GEN_VOLUME_SIZE}"

# Set auto-recovery
if [ -z ${NODE_RECOVERY} ]; then
    echo "[WARNING] NODE_RECOVERY environment variable is not set, set to Automatic."
    export NODE_RECOVERY="Automatic"
fi
echo "export NODE_RECOVERY=${NODE_RECOVERY}" >> env_vars
echo "[INFO] NODE_RECOVERY = ${NODE_RECOVERY}"
