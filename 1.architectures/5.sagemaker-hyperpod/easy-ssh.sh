#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

(( ! $# == 1 )) && { echo "Must define cluster name" ; exit -1 ; }

cluster_id=$(aws sagemaker describe-cluster --cluster-name $1 | jq '.ClusterArn' | awk -F/ '{gsub(/"/, "", $NF); print $NF}')
node_group="controller-machine"
instance_id=$(aws sagemaker list-cluster-nodes --cluster-name $1 --region us-west-2 --instance-group-name-contains ${node_group} | jq '.ClusterNodeSummaries[0].InstanceId' | tr -d '"')

echo "Cluster id: ${cluster_id}"
echo "Instance id: ${instance_id}"
echo "Node Group: ${node_group}"

echo "aws ssm start-session --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id}"

aws ssm start-session --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id}
