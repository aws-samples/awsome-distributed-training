#!/usr/bin/env bash

set -e
set -o pipefail

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <EKS_CLUSTER_NAME> <PROMETHEUS_GRAFANA_STACK> [<PARAMETERS>]"
    exit 1
  fi

EKS_CLUSTER_NAME=$1
PROMETHEUS_GRAFANA_STACK=$2
shift
shift



AMP_REMOTE_URI=$(aws cloudformation describe-stacks --stack-name $PROMETHEUS_GRAFANA_STACK --query 'Stacks[0].Outputs[?OutputKey==`AMPRemoteWriteURL`].OutputValue' --output text)
GRAFANA_URI=$(aws cloudformation describe-stacks --stack-name $PROMETHEUS_GRAFANA_STACK --query 'Stacks[0].Outputs[?OutputKey==`GrafanWorkspaceURL`].OutputValue' --output text)
REGION=$(aws cloudformation describe-stacks --stack-name $PROMETHEUS_GRAFANA_STACK --query 'Stacks[0].Outputs[?OutputKey==`Region`].OutputValue' --output text)

echo -e "\nFetched below details from Grafana Stack"
echo -e "\nAMP writer URI from stack : $AMP_REMOTE_URI"
echo -e "\nGRAFANA URI from stack : $GRAFANA_URI"
echo -e "\nREGION from stack : $REGION"


echo -e "\nInstalling cert manager on Cluster : $EKS_CLUSTER_NAME"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.1/cert-manager.yaml

echo -e "\nAssociating OIDC provider to your EKS cluster: $EKS_CLUSTER_NAME"
eksctl utils associate-iam-oidc-provider --region=$REGION --cluster=$EKS_CLUSTER_NAME --approve

echo -e "\nCreating an IAM role and Kubernetes Service Account so that EKS can send metrics to Amazon Managed Service for Prometheus"
eksctl create iamserviceaccount \
   --name adot-collector \
   --namespace default \
   --region $REGION \
   --cluster $EKS_CLUSTER_NAME \
   --attach-policy-arn arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess \
   --approve \
   --override-existing-serviceaccounts

echo -e "\nInstalling adot eks addon on EKS cluster: $EKS_CLUSTER_NAME"
aws eks create-addon --addon-name adot --addon-version v0.94.1-eksbuild.1 --cluster-name $EKS_CLUSTER_NAME

echo -e "\nTimeout for 60 seconds before deploying scrapper. Waiting for resources to complete creation"
sleep 60

echo -e "\nInstalling scrapper on EKS cluster: $EKS_CLUSTER_NAME to send metrics to Prometheus"
curl -O https://raw.githubusercontent.com/aws-observability/aws-otel-community/master/sample-configs/operator/collector-config-amp.yaml
sed -i '' "s|<YOUR_AWS_REGION>|$REGION|g" collector-config-amp.yaml
sed -i '' "s|<YOUR_REMOTE_WRITE_ENDPOINT>|$AMP_REMOTE_URI|g" collector-config-amp.yaml
kubectl apply -f collector-config-amp.yaml

echo -e "\nGrafana workspace link: $GRAFANA_URI"