
#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="hyperpod-ig-demo"
EKS_CLUSTER_NAME="hyperpod-ig-demo"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
EXECUTION_ROLE_ARN="$1"
SUBNET_ID="$2"
SECURITY_GROUP_ID="$3"

if [ -f cdk-outputs.json ]; then
  LIFECYCLE_BUCKET=$(python3 -c "
import json
with open('cdk-outputs.json') as f:
    d = json.load(f)
    print(d['HyperPodInferenceGatewayStack']['LifecycleBucketName'])
  ")
else
  LIFECYCLE_BUCKET="hyperpod-ig-demo-${AWS_ACCOUNT_ID:-000000000000}-${REGION}"
fi

EKS_ARN=$(aws eks describe-cluster \
  --name "${EKS_CLUSTER_NAME}" \
  --region "${REGION}" \
  --query 'cluster.arn' --output text)

echo "==> Creating HyperPod cluster: ${CLUSTER_NAME}"

aws sagemaker create-cluster \
  --cluster-name "${CLUSTER_NAME}" \
  --orchestrator "{\"Eks\":{\"ClusterArn\":\"${EKS_ARN}\"}}" \
  --vpc-config "{\"SecurityGroupIds\":[\"${SECURITY_GROUP_ID}\"],\"Subnets\":[\"${SUBNET_ID}\"]}" \
  --instance-groups "[
    {
      \"InstanceGroupName\": \"controller\",
      \"InstanceType\": \"ml.m5.2xlarge\",
      \"InstanceCount\": 1,
      \"LifeCycleConfig\": {
        \"SourceS3Uri\": \"s3://${LIFECYCLE_BUCKET}/lifecycle-scripts/\",
        \"OnCreate\": \"on_create.sh\"
      },
      \"ExecutionRole\": \"${EXECUTION_ROLE_ARN}\"
    },
    {
      \"InstanceGroupName\": \"gpu-workers\",
      \"InstanceType\": \"ml.g5.2xlarge\",
      \"InstanceCount\": 1,
      \"LifeCycleConfig\": {
        \"SourceS3Uri\": \"s3://${LIFECYCLE_BUCKET}/lifecycle-scripts/\",
        \"OnCreate\": \"on_create.sh\"
      },
      \"ExecutionRole\": \"${EXECUTION_ROLE_ARN}\"
    }
  ]" \
  --node-recovery "Automatic" \
  --region "${REGION}"

echo "==> Cluster creation initiated. Monitor:"
echo "    aws sagemaker describe-cluster --cluster-name ${CLUSTER_NAME} --region ${REGION}"
echo "==> Once InService, apply security group fix (see README Step 5)."
echo "==> Then install add-ons from SageMaker Console:"
echo "    HyperPod Clusters → ${CLUSTER_NAME} → Inference → Quick Install"

