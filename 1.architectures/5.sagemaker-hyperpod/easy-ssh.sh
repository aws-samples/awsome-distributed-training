#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

declare -a HELP=(
    "[-h|--help]"
    "[-c|--controller-group]"
    "[-r|--region]"
    "[-p|--profile]"
    "CLUSTER_NAME"
)

cluster_name=""
node_group="controller-machine"
declare -a aws_cli_args=()

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
        -r|--region)
            aws_cli_args+=(--region "$2")
            shift 2
            ;;
        -p|--profile)
            aws_cli_args+=(--profile "$2")
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
cluster_id=$(aws sagemaker describe-cluster "${aws_cli_args[@]}" --cluster-name $cluster_name | jq '.ClusterArn' | awk -F/ '{gsub(/"/, "", $NF); print $NF}')
instance_id=$(aws sagemaker list-cluster-nodes "${aws_cli_args[@]}" --cluster-name $cluster_name --instance-group-name-contains ${node_group} | jq '.ClusterNodeSummaries[0].InstanceId' | tr -d '"')

echo "Cluster id: ${cluster_id}"
echo "Instance id: ${instance_id}"
echo "Node Group: ${node_group}"

echo -e "aws ssm start-session "${aws_cli_args[@]}" --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id}"

echo -e "Add the following to your ~/.ssh/config to easily connect:"
echo "
cat <<EOF >> ~/.ssh/config
Host ${cluster_name}
  User ubuntu
  ProxyCommand sh -c \"aws ssm start-session ${aws_cli_args[@]} --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id} --document-name AWS-StartSSHSession --parameters 'portNumber=%p'\"
EOF

Add your ssh keypair and then you can do:

$ ssh ${cluster_name}
"

aws ssm start-session "${aws_cli_args[@]}" --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id}
