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
set -exo pipefail
: "${STACK_ID_VPC:=sagemaker-hyperpod}"

declare -a HELP=(
    "[-h|--help]"
    "[-r|--region]"
    "[-p|--profile]"
    "[-s|--stack-id-vpc]"
    "[-i|--instance-type]"
    "[-c|--instance-count]"
    "[-d|--dry-run]"
    "CLUSTER_NAME"
)
declare -a aws_cli_args=()
DRY_RUN=0


parse_args() {
    local key
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
        -h|--help)
            echo "Create a HyperPod Cluster with single partition." 
            echo "It requires sageamker-hyperpod CloudFormation stack to be deployed." 
            echo "Usage: $(basename ${BASH_SOURCE[0]}) ${HELP[@]}"
            exit 0
            ;;
        -r|--region)
            aws_cli_args+=(--region "$2")
            AWS_REGION="$2"
            shift 2
            ;;
        -p|--profile)
            aws_cli_args+=(--profile "$2")
            shift 2
            ;;
        -s|--stack-id-vpc)
            STACK_ID_VPC="$2"
            shift 2
            ;;
        -i|--instance-type)
            INSTANCE="$2"
            shift 2
            ;;
        -c|--instance-count)
            INSTANCE_COUNTS="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=1
            shift
            ;;
        *)
            CLUSTER_NAME="$key" 
            shift
            ;;
        esac
    done
}

parse_args $@

mkdir $CLUSTER_NAME && cd $CLUSTER_NAME

# Check for AWS CLI
if ! command -v aws &> /dev/null
then
    echo -e "please install aws..."
    echo -e "see https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html for the installation guide"
    exit 1
fi

# Check for JQ
if ! command -v jq &> /dev/null
then
    echo -e "please install jq...\nsudo yum install -y jq or brew install jq"
    exit 1
fi

# Define cluster name
if [ -z ${CLUSTER_NAME} ]; then
    echo "[WARNING] CLUSTER_NAME environment variable is not set, automatically set to ml-cluster"
    CLUSTER_NAME=ml-cluster
fi

# Define stack name
if [ -z ${STACK_ID_VPC} ]; then
    echo "[WARNING] STACK_ID_VPC environment variable is not set, automatically set to sagemaker-hyperpod"
    STACK_ID_VPC=sagemaker-hyperpod
fi

# Define AWS Region
if [ -z ${AWS_REGION} ]; then
    echo "[WARNING] AWS_REGION environment variable is not set, automatically set depending on aws cli default region."
    export AWS_REGION=$(aws configure get region)
fi
echo "export AWS_REGION=${AWS_REGION}" >> env_vars
echo "[INFO] AWS_REGION = ${AWS_REGION}"

# Define Instances seperated by ','.
if [ -z ${INSTANCE} ]; then
    echo "[WARNING] INSTANCE environment variable is not set, automatically set to g5.12xlarge."
    export INSTANCE=g5.12xlarge
fi
echo "export INSTANCE=${INSTANCE}" >> env_vars
echo "[INFO] INSTANCE = ${INSTANCE}"

# Define Instance counts seperated by ','.
if [ -z ${INSTANCE_COUNT} ]; then
    echo "[WARNING] INSTANCE_COUNTS environment variable is not set, automatically set to 2."
    export INSTANCE_COUNT=2
fi

# Retrieve VPC ID
export VPC_ID=`aws cloudformation describe-stacks \
    --stack-name $STACK_ID_VPC \
    --query 'Stacks[0].Outputs[?OutputKey==\`VPC\`].OutputValue' \
    --region ${AWS_REGION} \
    --output text`

if [[ ! -z $VPC_ID ]]; then
    echo "export VPC_ID=${VPC_ID}" >> env_vars
    echo "[INFO] VPC_ID = ${VPC_ID}"
else
    echo "[ERROR] failed to retrieve VPC ID"
    return 1
fi

# Grab the subnet id
export SUBNET_ID=`aws cloudformation describe-stacks \
    --stack-name $STACK_ID_VPC \
    --query 'Stacks[0].Outputs[?OutputKey==\`PrimaryPrivateSubnet\`].OutputValue' \
    --region ${AWS_REGION} \
    --output text`

if [[ ! -z $SUBNET_ID ]]; then
    echo "export SUBNET_ID=${SUBNET_ID}" >> env_vars
    echo "[INFO] SUBNET_ID = ${SUBNET_ID}"
else
    echo "[ERROR] failed to retrieve SUBNET ID"
    return 1
fi

# Grab the subnet id
export PUBLIC_SUBNET_ID=`aws cloudformation describe-stacks \
    --stack-name $STACK_ID_VPC \
    --query 'Stacks[0].Outputs[?OutputKey==\`PublicSubnet\`].OutputValue' \
    --region ${AWS_REGION} \
    --output text`

if [[ ! -z $PUBLIC_SUBNET_ID ]]; then
    echo "export PUBLIC_SUBNET_ID=${PUBLIC_SUBNET_ID}" >> env_vars
    echo "[INFO] PUBLIC_SUBNET_ID = ${PUBLIC_SUBNET_ID}"
else
    echo "[ERROR] failed to retrieve Public SUBNET ID"
    return 1
fi

# Get FSx Filesystem id from CloudFormation
export FSX_ID=`aws cloudformation describe-stacks \
    --stack-name $STACK_ID_VPC \
    --query 'Stacks[0].Outputs[?OutputKey==\`FSxLustreFilesystemId\`].OutputValue' \
    --region ${AWS_REGION} \
    --output text`

if [[ ! -z $FSX_ID ]]; then
    echo "export FSX_ID=${FSX_ID}" >> env_vars
    echo "[INFO] FSX_ID = ${FSX_ID}"
else
    echo "[ERROR] failed to retrieve FSX ID"
    return 1
fi

# Get FSx Filesystem Mountname from CloudFormation
export FSX_MOUNTNAME=`aws cloudformation describe-stacks \
    --stack-name $STACK_ID_VPC \
    --query 'Stacks[0].Outputs[?OutputKey==\`FSxLustreFilesystemMountname\`].OutputValue' \
    --region ${AWS_REGION} \
    --output text`

if [[ ! -z $FSX_MOUNTNAME ]]; then
    echo "export FSX_MOUNTNAME=${FSX_MOUNTNAME}" >> env_vars
    echo "[INFO] FSX_MOUNTNAME = ${FSX_MOUNTNAME}"
else
    echo "[ERROR] failed to retrieve FSX Mountname"
    return 1
fi

# Get FSx Security Group from CloudFormation
export SECURITY_GROUP=`aws cloudformation describe-stacks \
    --stack-name $STACK_ID_VPC \
    --query 'Stacks[0].Outputs[?OutputKey==\`SecurityGroup\`].OutputValue' \
    --region ${AWS_REGION} \
    --output text`

if [[ ! -z $SECURITY_GROUP ]]; then
    echo "export SECURITY_GROUP=${SECURITY_GROUP}" >> env_vars
    echo "[INFO] SECURITY_GROUP = ${SECURITY_GROUP}"
else
    echo "[ERROR] failed to retrieve FSX Security Group"
    return 1
fi

# Get sagemaker role ARN 
export ROLE=`aws cloudformation describe-stacks \
    --stack-name $STACK_ID_VPC \
    --query 'Stacks[0].Outputs[?OutputKey==\`AmazonSagemakerClusterExecutionRoleArn\`].OutputValue' \
    --region ${AWS_REGION} \
    --output text`

if [[ ! -z $ROLE ]]; then
    echo "export ROLE=${ROLE}" >> env_vars
    echo "[INFO] ROLE = ${ROLE}"
else
    echo "[ERROR] failed to retrieve Role ARN"
    return 1
fi

# Get sagemaker role ROLENAME 
export ROLENAME=$(basename "$ROLE")

if [[ ! -z $ROLENAME ]]; then
    echo "export ROLENAME=${ROLENAME}" >> env_vars
    echo "[INFO] ROLENAME = ${ROLENAME}"
else
    echo "[ERROR] failed to retrieve Role NAME"
    return 1
fi

# Get s3 bucket name
export BUCKET=`aws cloudformation describe-stacks \
    --stack-name $STACK_ID_VPC \
    --query 'Stacks[0].Outputs[?OutputKey==\`AmazonS3BucketName\`].OutputValue' \
    --region ${AWS_REGION} \
    --output text`

if [[ ! -z $BUCKET ]]; then
    echo "export BUCKET=${BUCKET}" >> env_vars
    echo "[INFO] BUCKET = ${BUCKET}"
else
    echo "[ERROR] failed to retrieve Bucket Name"
    return 1
fi


git clone --depth=1 https://github.com/aws-samples/awsome-distributed-training/
# Use pushd and popd to navigate directories https://en.wikipedia.org/wiki/Pushd_and_popd
pushd awsome-distributed-training/1.architectures/5.sagemaker-hyperpod/LifecycleScripts/
# upload data
aws s3 cp --recursive base-config/ s3://${BUCKET}/src
# move back to the previous directory
popd

cat > provisioning_parameters.json << EOL
{
  "version": "1.0.0",
  "workload_manager": "slurm",
  "controller_group": "controller-machine",
  "worker_groups": [
    {
      "instance_group_name": "worker-group-1",
      "partition_name": ${INSTANCE}
    }
  ],
  "fsx_dns_name": "${FSX_ID}.fsx.${AWS_REGION}.amazonaws.com",
  "fsx_mountname": "${FSX_MOUNTNAME}"
}
EOL

# copy to the S3 Bucket
aws s3 cp provisioning_parameters.json s3://${BUCKET}/src/

cat > cluster-config.json << EOL
{
    "ClusterName": "${CLUSTER_NAME}",
    "InstanceGroups": [
      {
        "InstanceGroupName": "controller-machine",
        "InstanceType": "ml.m5.12xlarge",
        "InstanceCount": 1,
        "LifeCycleConfig": {
          "SourceS3Uri": "s3://${BUCKET}/src",
          "OnCreate": "on_create.sh"
        },
        "ExecutionRole": "${ROLE}",
        "ThreadsPerCore": 1
      },
      {
        "InstanceGroupName": "worker-group-1",
        "InstanceType": "ml.${INSTANCE}",
        "InstanceCount": ${INSTANCE_COUNT},
        "LifeCycleConfig": {
          "SourceS3Uri": "s3://${BUCKET}/src",
          "OnCreate": "on_create.sh"
        },
        "ExecutionRole": "${ROLE}",
        "ThreadsPerCore": 1
      }
    ],
    "VpcConfig": {
      "SecurityGroupIds": ["$SECURITY_GROUP"],
      "Subnets":["$SUBNET_ID"]
    }
}
EOL

# Validate Cluster configuration
wget https://raw.githubusercontent.com/aws-samples/awsome-distributed-training/main/1.architectures/5.sagemaker-hyperpod/validate-config.py
# install boto3
pip3 install boto3
# check config for known issues
python3 validate-config.py --cluster-config cluster-config.json --provisioning-parameters provisioning_parameters.json

echo "aws sagemaker create-cluster --cli-input-json file://cluster-config.json --region ${REGION}"
[[ DRY_RUN -eq 1 ]] && exit 0
aws sagemaker create-cluster --cli-input-json "file://cluster-config.json" --region ${REGION}