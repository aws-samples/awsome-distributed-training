#!/bin/bash

# Get Private Subnet ID
export private_subnet_id=$(aws cloudformation --region us-west-2 describe-stacks --query "Stacks[?StackName=='create-large-scale-vpc-stack'][].Outputs[?OutputKey=='PrivateSubnet'].OutputValue" --output text)

echo "Private Subnet ID: ${private_subnet_id}"

# Get Public Subnet ID
export public_subnet_id=$(aws cloudformation --region us-west-2 describe-stacks --query "Stacks[?StackName=='create-large-scale-vpc-stack'][].Outputs[?OutputKey=='PublicSubnet'].OutputValue" --output text)

echo "Public Subnet ID: ${public_subnet_id}"

# Get AMI ID
export ami_id=$( aws ec2 describe-images --region us-west-2 --filters "Name=name,Values=pcluster-dist-training-ami-*" --query 'Images[*].[ImageId]' --output text)

echo "AMI ID: ${ami_id}"

#List Keys
aws ec2 describe-key-pairs --query "KeyPairs[*].{KeyPairId:KeyPairId,KeyName:KeyName,KeyType:KeyType}" --output table

# Update Cluster creation config template
cat create-cluster-template.yaml | envsubst > create-cluster.yaml

# Create Cluster
pcluster create-cluster --cluster-configuration create-cluster.yaml --cluster-name pcluster-ml --region us-west-2 --suppress-validators "type:InstanceTypeBaseAMICompatibleValidator" --rollback-on-failure "false"



 
