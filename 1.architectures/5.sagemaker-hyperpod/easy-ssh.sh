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
    else
        echo -e "${BLUE}Would you like to add ${GREEN}${cluster_name}${BLUE} to  ~/.ssh/config (yes/no)?${NC}"
        read -p "> " ADD_CONFIG

        if [[ $ADD_CONFIG == "yes" ]]; then
            if [ ! -f ~/.ssh/config ]; then
                mkdir -p ~/.ssh
                touch ~/.ssh/config
            fi
            echo -e "${GREEN}✅ adding ml-cluster to  ~/.ssh/config:${NC}"
            cat <<EOL >> ~/.ssh/config 
Host ${cluster_name}
    User ubuntu
    ProxyCommand sh -c "aws ssm start-session ${aws_cli_args[@]} --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id} --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
EOL
        else
            echo -e "${GREEN}❌ skipping adding ml-cluster to  ~/.ssh/config:"
        fi      
    fi
}

escape_spaces() {
    local input="$1"
    echo "${input// /\\ }"
}

# Function to add the user's SSH public key to the cluster
add_keypair_to_cluster() {
    PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)

    # Check if the fingerprint already exists in the cluster's authorized_keys
    EXISTING_KEYS=$(aws ssm start-session --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id} --document-name AmazonEKS-ExecuteNonInteractiveCommand --parameters command="cat /fsx/ubuntu/.ssh/authorized_keys")
    
    if echo "$EXISTING_KEYS" | grep -q "$PUBLIC_KEY"; then
        echo -e "${BLUE}2. Detected SSH public key ${GREEN}~/.ssh/id_rsa.pub${BLUE} on the cluster. Skipping adding...${NC}" 
        return
    else
        echo -e "${BLUE}2. Do you want to add your SSH public key ${GREEN}~/.ssh/id_rsa.pub${BLUE} to the cluster (yes/no)?${NC}" 
        read -p "> " ADD_KEYPAIR
        if [[ $ADD_KEYPAIR == "yes" ]]; then
            echo "Adding ... ${PUBLIC_KEY}"
            command="sed -i \$a$(escape_spaces "$PUBLIC_KEY") /fsx/ubuntu/.ssh/authorized_keys"
            aws ssm start-session --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id}  --document-name AmazonEKS-ExecuteNonInteractiveCommand  --parameters command="$command"
            echo "✅ Your SSH public key ~/.ssh/id_rsa.pub has been added to the cluster."
        else
            echo "❌ Skipping adding SSH public key to the cluster."
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

check_ssh_config
add_keypair_to_cluster

echo -e "\nNow you can run:\n"
echo -e "$ ${GREEN}ssh ${cluster_name}${NC}"

[[ DRY_RUN -eq 1 ]] && echo -e  "\n${GREEN}aws ssm start-session "${aws_cli_args[@]}" --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id}${NC}\n" && exit 0

# Start session as Ubuntu only if the SSM-SessionManagerRunShellAsUbuntu document exists.
if aws ssm describe-document "${aws_cli_args[@]}" --name SSM-SessionManagerRunShellAsUbuntu > /dev/null 2>&1; then
    aws ssm start-session "${aws_cli_args[@]}" --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id} --document SSM-SessionManagerRunShellAsUbuntu
else
    aws ssm start-session "${aws_cli_args[@]}" --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id}
fi
