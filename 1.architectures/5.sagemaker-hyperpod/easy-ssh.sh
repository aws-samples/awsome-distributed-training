#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

declare -a HELP=(
    "[-h|--help]"
    "[-c|--controller-group]"
    "[-r|--region]"
    "[-p|--profile]"
    "[-d|--dry-run]"
    "CLUSTER_NAME"
)

cluster_name=""
node_group="controller-machine"
declare -a aws_cli_args=()
DRY_RUN=0

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
        -d|--dry-run)
            DRY_RUN=1
            shift
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

# Function to check if ml-cluster exists in ~/.ssh/config
check_ssh_config() {
    if grep -q "Host ${cluster_name}" ~/.ssh/config; then
        echo -e "${BLUE}1. Detected ${GREEN}${cluster_name}${BLUE} in  ${GREEN}~/.ssh/config${BLUE}. Skipping adding...${NC}"

        echo -e "\nFYI instead of this script you can do:\n"
        echo -e "$ ${GREEN}ssh ${cluster_name}${NC}"
    else
        echo -e "${BLUE}Would you like to add ${GREEN}${cluster_name}${BLUE} to  ~/.ssh/config (yes/no)?${NC}"
        read -p "> " ADD_CONFIG

        if [[ $ADD_CONFIG == "yes" ]]; then
            echo -e "${GREEN}✅ adding ml-cluster to  ~/.ssh/config:${NC}"
            cat <<EOL >> ~/.ssh/config 
Host ${cluster_name}
    User ubuntu
    ProxyCommand sh -c "aws ssm start-session ${aws_cli_args[@]} --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id} --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
EOL
            echo -e "\nNext add your ssh public key to ~/.ssh/authorized_keys on the cluster and then you can do:\n"
            echo -e "$ ${GREEN}ssh ${cluster_name}${NC}"
        else
            echo -e "${GREEN}❌ skipping adding ml-cluster to  ~/.ssh/config:"
        fi      
    fi
}

parse_args $@

#===Style Definitions===
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print a yellow header
print_header() {
    echo -e "\n${BLUE}=================================================${NC}"
    echo -e "\n${YELLOW}==== $1 ====${NC}\n"
    echo -e "\n${BLUE}=================================================${NC}"

}


print_header "🚀 HyperPod Cluster Easy SSH Script! 🚀"

cluster_id=$(aws sagemaker describe-cluster "${aws_cli_args[@]}" --cluster-name $cluster_name | jq '.ClusterArn' | awk -F/ '{gsub(/"/, "", $NF); print $NF}')
instance_id=$(aws sagemaker list-cluster-nodes "${aws_cli_args[@]}" --cluster-name $cluster_name --instance-group-name-contains ${node_group} | jq '.ClusterNodeSummaries[0].InstanceId' | tr -d '"')

# print_header
echo -e "Cluster id: ${GREEN}${cluster_id}${NC}"
echo -e "Instance id: ${GREEN}${instance_id}${NC}"
echo -e "Node Group: ${GREEN}${node_group}${NC}"

echo -e "\naws ssm start-session "${aws_cli_args[@]}" --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id} --document SSM-SessionManagerRunShellAsUbuntu\n"

check_ssh_config

[[ DRY_RUN -eq 1 ]] && exit 0

aws ssm start-session "${aws_cli_args[@]}" --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id} --document SSM-SessionManagerRunShellAsUbuntu
