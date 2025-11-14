#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

declare -a HELP=(
    "[-h|--help]"
    "[-c|--controller-group]"
    "[-u|--user]"
    "[-r|--region]"
    "[-p|--profile]"
    "[-d|--dry-run]"
    "CLUSTER_NAME"
)

cluster_name=""
node_group="controller-machine"
ssh_user="ubuntu"
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
            echo ""
            echo "Options:"
            echo "  -h, --help              Show this help message"
            echo "  -c, --controller-group  Specify the controller group name (default: controller-machine)"
            echo "  -u, --user              Specify the SSH user (default: ubuntu)"
            echo "  -r, --region            Specify AWS region"
            echo "  -p, --profile           Specify AWS profile"
            echo "  -d, --dry-run           Show the SSM command without executing"
            echo ""
            echo "Examples:"
            echo "  $(basename ${BASH_SOURCE[0]}) ml-cluster"
            echo "  $(basename ${BASH_SOURCE[0]}) -c login-group ml-cluster"
            echo "  $(basename ${BASH_SOURCE[0]}) -u user1 ml-cluster"
            echo "  $(basename ${BASH_SOURCE[0]}) -u user2 -r us-west-2 ml-cluster"
            echo ""
            echo "Note: For non-ubuntu users, ensure your IAM user has the SSMSessionRunAs tag"
            echo "      set to the desired OS username for passwordless login."
            exit 0
            ;;
        -c|--controller-group)
            node_group="$2"
            shift 2
            ;;
        -u|--user)
            ssh_user="$2"
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

# Function to check if cluster config exists in ~/.ssh/config
check_ssh_config() {
    local ssh_host="${cluster_name}"
    
    # If user is not ubuntu, append username to host for unique config entry
    if [[ "$ssh_user" != "ubuntu" ]]; then
        ssh_host="${cluster_name}-${ssh_user}"
    fi
    
    if grep -wq "Host ${ssh_host}$" ~/.ssh/config; then
        echo -e "${BLUE}1. Detected ${GREEN}${ssh_host}${BLUE} in ${GREEN}~/.ssh/config${BLUE}. Skipping adding...${NC}"
    else
        echo -e "${BLUE}Would you like to add ${GREEN}${ssh_host}${BLUE} to ~/.ssh/config (yes/no)?${NC}"
        read -p "> " ADD_CONFIG

        if [[ $ADD_CONFIG == "yes" ]]; then
            if [ ! -f ~/.ssh/config ]; then
                mkdir -p ~/.ssh
                touch ~/.ssh/config
            fi
            echo -e "${GREEN}✅ adding ${ssh_host} to ~/.ssh/config:${NC}"
            cat <<EOL >> ~/.ssh/config 
Host ${ssh_host}
    User ${ssh_user}
    ProxyCommand sh -c "aws ssm start-session ${aws_cli_args[@]} --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id} --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
EOL
        else
            echo -e "${GREEN}❌ skipping adding ${ssh_host} to ~/.ssh/config${NC}"
        fi      
    fi
    
    # Store the ssh_host for later use
    SSH_HOST="${ssh_host}"
}

escape_spaces() {
    local input="$1"
    echo "${input// /\\ }"
}

# Function to add the user's SSH public key to the cluster
add_keypair_to_cluster() {
    PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)
    
    # Determine the authorized_keys path based on user and filesystem
    # Check if OpenZFS is mounted (home directory would be /home/username)
    local auth_keys_path="/fsx/${ssh_user}/.ssh/authorized_keys"
    
    # Try to detect if user home is on OpenZFS
    local home_check=$(aws ssm start-session --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id} --document-name AmazonEKS-ExecuteNonInteractiveCommand --parameters command="getent passwd ${ssh_user} | cut -d: -f6" 2>/dev/null || echo "")
    
    if echo "$home_check" | grep -q "^/home/${ssh_user}"; then
        # User home is on OpenZFS, but .ssh is symlinked to /fsx
        auth_keys_path="/fsx/${ssh_user}/.ssh/authorized_keys"
    fi

    # Check if the fingerprint already exists in the cluster's authorized_keys
    EXISTING_KEYS=$(aws ssm start-session --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id} --document-name AmazonEKS-ExecuteNonInteractiveCommand --parameters command="cat ${auth_keys_path}" 2>/dev/null || echo "")
    
    if echo "$EXISTING_KEYS" | grep -q "$PUBLIC_KEY"; then
        echo -e "${BLUE}2. Detected SSH public key ${GREEN}~/.ssh/id_rsa.pub${BLUE} for user ${GREEN}${ssh_user}${BLUE} on the cluster. Skipping adding...${NC}" 
        return
    else
        echo -e "${BLUE}2. Do you want to add your SSH public key ${GREEN}~/.ssh/id_rsa.pub${BLUE} to user ${GREEN}${ssh_user}${BLUE} on the cluster (yes/no)?${NC}" 
        read -p "> " ADD_KEYPAIR
        if [[ $ADD_KEYPAIR == "yes" ]]; then
            echo "Adding ... ${PUBLIC_KEY}"
            command="sed -i \$a$(escape_spaces "$PUBLIC_KEY") ${auth_keys_path}"
            aws ssm start-session --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id}  --document-name AmazonEKS-ExecuteNonInteractiveCommand  --parameters command="$command"
            echo "✅ Your SSH public key ~/.ssh/id_rsa.pub has been added to user ${ssh_user} on the cluster."
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

# Exit immediately if cluster or instance ID is not found.
if [[ -z "$cluster_id" || -z "$instance_id" ]]; then
    echo "Error: Cluster or instance not found for the specified cluster name (${cluster_name}). Exiting."
    exit 1
fi

# print_header
echo -e "Cluster id: ${GREEN}${cluster_id}${NC}"
echo -e "Instance id: ${GREEN}${instance_id}${NC}"
echo -e "Node Group: ${GREEN}${node_group}${NC}"
echo -e "SSH User: ${GREEN}${ssh_user}${NC}"

check_ssh_config
add_keypair_to_cluster

echo -e "\nNow you can run:\n"
echo -e "$ ${GREEN}ssh ${SSH_HOST}${NC}"

[[ DRY_RUN -eq 1 ]] && echo -e  "\n${GREEN}aws ssm start-session "${aws_cli_args[@]}" --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id}${NC}\n" && exit 0

# Determine which SSM document to use based on the user
if [[ "$ssh_user" == "ubuntu" ]]; then
    # Start session as Ubuntu if the SSM-SessionManagerRunShellAsUbuntu document exists
    if aws ssm describe-document "${aws_cli_args[@]}" --name SSM-SessionManagerRunShellAsUbuntu > /dev/null 2>&1; then
        aws ssm start-session "${aws_cli_args[@]}" --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id} --document SSM-SessionManagerRunShellAsUbuntu
    else
        aws ssm start-session "${aws_cli_args[@]}" --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id}
    fi
else
    # For non-ubuntu users, check if they have an IAM user with SSMSessionRunAs tag
    echo -e "${BLUE}Connecting as user: ${GREEN}${ssh_user}${NC}"
    echo -e "${YELLOW}Note: Make sure the IAM user has the SSMSessionRunAs tag set to '${ssh_user}' for passwordless login${NC}"
    echo -e "${YELLOW}See: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html${NC}"
    
    # Use standard SSM session - the SSMSessionRunAs tag on the IAM user will determine which OS user to use
    aws ssm start-session "${aws_cli_args[@]}" --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id}
fi
