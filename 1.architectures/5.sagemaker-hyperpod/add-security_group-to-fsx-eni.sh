#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

declare -a HELP=(
    "[-p|--profile]"
    "[-r|--region]"
    "[-f|--fsx-id]"
    "[-s|--sg-id]"
)

fsx_id=""
security_group=""
declare -a awscli_args=()

parse_args() {
    local key
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
        -h|--help)
            echo "Add security groups to existing Amazon FSx for Lustre ENI."
            echo "Usage: $(basename ${BASH_SOURCE[0]}) ${HELP[@]}"
            ;;
        -p|--profile)
            awscli_args+=(--profile "$2")
            shift 2
        ;;
        -r|--region)
            awscli_args+=(--region "$2")
            shift 2
            ;;
        -s|--sg-id)
            security_group="$2"
            shift 2
            ;;
        -f|--fsx-id)
            fsx_id="$2"
            shift 2
            ;;
        *)
            [[ "$fsx_id" == "" ]] \
                && $fsx_id="$key" \
                || { echo "Must define one file system id." ; exit -1; }
            [[ "$security_group" == "" ]] \
                && $security_group="$key" \
                || { echo "Must define at least one security group id." ; exit -1; }
            shift
            ;;
        esac
    done

    [[ "$fsx_id" == "" ]] || [[ "$security_group" == "" ]] && { echo "Must define at least one filesystem ID and security group ID"; exit -1; }
}

#===Style Definitions===
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}=================================================${NC}"
    echo -e "\n${YELLOW} $1 "
    echo -e "\n${BLUE}=================================================${NC}"
}

#### __main__ ####
parse_args $@

print_header "    🚀 Amazon Sagemaker Hyperpod 🚀 \n \
   Amazon FSx for Lustre helper tool \n \
   This tool will help by adding new \n \
security groups to the FSx for Lustre ENIs"

# First get one network interface then describe the network interface to get existing Security Groups attached
fsx_id_enis=$(aws fsx describe-file-systems "${awscli_args[@]}" --query 'FileSystems[0].NetworkInterfaceIds' --output text)
existing_sg=$(aws ec2 describe-network-interfaces "${awscli_args[@]}" --network-interface-ids $fsx_id_enis --query 'NetworkInterfaces[0].Groups[*].GroupId' --output text)

if [[ -z "$fsx_id_enis" || -z "$existing_sg" ]]; then
    echo -e "Error: No ENI or existing security group found. Exiting."
    exit 1
fi 

echo -e "Amazon FSx for Lustre filesystem: ${GREEN}${fsx_id}${NC}"
echo -e "Existing security groups attached on the filesystem: ${GREEN}${existing_sg}${NC}"
echo -e "Adding security group ID: ${GREEN}${security_group}${NC}"

# Finally update the ENI to add the new security groups plus the existing security groups
for i in $fsx_id_enis; do 
    echo -e "Adding ${GREEN}${security_group} to ENI ${GREEN}${$i}"
    aws ec2 modify-network-interface-attribute "${awscli_args[@]}" --network-interface-id $i --groups $existing_sg $security_group

    [[ $? -ne 0 ]] && { echo "Failed adding $security_group to ENI $i"; exit -1; }
done

