#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

declare -a HELP=(
    "[-h|--help]"
    "[-c|--controller-group]"
    "CLUSTER_NAME"
)

cluster_name=""
node_group="controller-machine"

parse_args() {
    local key
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
        -h|--help)
            echo "Access a HyperPod Slurm controller via ssh-over-ssm."
            echo "Usage: $(basename ${BASH_SOURCE[0]}) ${HELP[@]}"
            exit 0
            ;;
        -c|--controller-group)
            node_group="$2"
            shift 2
            ;;
        *)
            [[ "$cluster_name" == "" ]] \
                && cluster_name="$key" \
                || { echo "Must define one cluster name only" ; exit -1 ;  }
            shift
            ;;
        esac
    done

    [[ "$cluster_name" == "" ]] && { echo "Must define a cluster name" ; exit -1 ;  }
}

parse_args $@
cluster_id=$(aws sagemaker describe-cluster --cluster-name $cluster_name | jq '.ClusterArn' | awk -F/ '{gsub(/"/, "", $NF); print $NF}')
instance_id=$(aws sagemaker list-cluster-nodes --cluster-name $1 --region us-west-2 --instance-group-name-contains ${node_group} | jq '.ClusterNodeSummaries[0].InstanceId' | tr -d '"')

echo "Cluster id: ${cluster_id}"
echo "Instance id: ${instance_id}"
echo "Node Group: ${node_group}"

echo "aws ssm start-session --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id}"

aws ssm start-session --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id}
