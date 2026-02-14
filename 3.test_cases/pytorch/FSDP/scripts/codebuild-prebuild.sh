#!/bin/bash
set -e

echo "============================================================"
echo "Pre-build Phase"
echo "============================================================"

pip install --quiet boto3 awscli
export AWS_DEFAULT_REGION=${AWS_REGION}
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"

echo "Logging in to Amazon ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

export SKILL_PATH="${HOME}/.opencode/skills"
export SHARED_PATH="${SKILL_PATH}/shared"

if [ ! -d "${SKILL_PATH}/docker-image-builder" ]; then
    echo "Installing skills from repository..."
    mkdir -p ${SKILL_PATH}
    cp -r opencode/skills/* ${SKILL_PATH}/
fi

echo "Build Configuration: Project=${PROJECT_NAME}, Repository=${ECR_REPOSITORY}, Region=${AWS_REGION}"
