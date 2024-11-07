#!/bin/bash

# Workshop Automation Script
# This script automates the steps of the workshop by executing CLI commands

# Exit immediately if a command exits with a non-zero status.
set -e

#===Global===
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export AWS_REGION=$(aws configure get region)
TOTAL_STEPS=5
CURRENT_STEP=0

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

# UX Function for a Progress Bar :)
progress_bar() {
    local duration=$1
    local steps=$2
    local width=50
    local progress=0

    for ((i=0; i<steps; i++)); do
        progress=$(( (i * width) / steps ))
        printf "\r[%-${width}s] %d%%" "$(printf '#%.0s' $(seq 1 $progress))" "$(( (progress * 100) / width ))"
        sleep 0.1
    done
    echo        
}

#===Function Definitions===

# Helper function to install AWS CLI depending on OS
install_aws_cli() {
    DEVICE=$(uname)
    OS=$(uname -m)

    if [[ $DEVICE == *"Darwin"* ]]; then
        curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
        sudo installer -pkg AWSCLIV2.pkg -target /
        rm AWSCLIV2.pkg
    elif [[ $DEVICE == *"Linux"* ]]; then   
        if [[ $OS == *"x86_64"* ]]; then
            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        elif [[ $OS == *"aarch64"* ]]; then
            curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
        else
            echo "Unsupported Linux architecture: $OS. Please check https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html to install manually"
            exit 1    
        fi
        unzip awscliv2.zip
        sudo ./aws/install --update
        rm -rf aws awscliv2.zip
    else
        echo "Unsupported device: $DEVICE. Please check https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html to install manually"    
    fi
}

# Function to check the AWS CLI version and install/update as required
check_and_install_aws_cli() {
    echo -e "${BLUE}=== Checking AWS CLI Installation ===${NC}"

    if ! command -v aws &> /dev/null; then
        echo -e "${YELLOW}⚠️  AWS CLI is not installed. Installing...${NC}"
        install_aws_cli
    else
        echo -e "${GREEN}✅ AWS CLI found. Checking version...${NC}"
        CLI_VERSION=$(aws --version | awk '{print $1}' | cut -d/ -f2)

        echo -e "${BLUE}Current version: ${YELLOW}$CLI_VERSION${NC}"
        echo -e "${BLUE}Min. required version: ${YELLOW}2.17.1${NC}"

        if [[ "$(printf '%s\n' "2.17.1" "$CLI_VERSION" | sort -V | head -n1)" != "2.17.1" ]]; then
            echo -e "${YELLOW}⚠️  AWS CLI version $CLI_VERSION is lower than required.${NC}"
            echo -e "${YELLOW}   Updating AWS CLI...${NC}"
            install_aws_cli
        else
            echo -e "${GREEN}✅ AWS CLI version $CLI_VERSION is up to date.${NC}"
        fi
    fi     

    echo -e "${BLUE}=== AWS CLI Check Complete ===${NC}\n"

}

# Function to check if Git is installed and configured
check_git() {
    if ! command -v git &> /dev/null; then
        echo "Git is not installed. Please install Git and try again."
        exit 1
    fi
}

# Function to setup environment variables
setup_env_vars() {
    echo -e "${BLUE}=== Setting Up Environment Variables ===${NC}"

    echo -e "${YELLOW}Downloading configuration script...${NC}"
    curl 'https://static.us-east-1.prod.workshops.aws/public/4a96b723-a0e8-46c0-a78f-0dc6a37d8f0d/static/scripts/create_config.sh' --output create_config.sh
    echo -e "${GREEN}✅ Configuration script downloaded${NC}"
    
    echo -e "${BLUE}Enter CloudFormation stack name (default: sagemaker-hyperpod):${NC}"
    read -e CF_STACK_NAME
    CF_STACK_NAME=${CF_STACK_NAME:-sagemaker-hyperpod}

    if [ "$CF_STACK_NAME" != "sagemaker-hyperpod" ]; then
        # Replace 'sagemaker-hyperpod' with the user-provided stack name in the create_config.sh script    
        echo -e "${YELLOW}Using custom stack name: ${GREEN}$CF_STACK_NAME${NC}"
        echo -e "${BLUE}Updating configuration script...${NC}"
        sed -i.bak "s/\${STACK_ID_VPC:=sagemaker-hyperpod}/\${STACK_ID_VPC:=$CF_STACK_NAME}/" create_config.sh
        rm create_config.sh.bak
        echo -e "${GREEN}✅ Configuration script updated${NC}"
    else
        echo -e "${GREEN}Using default stack name: sagemaker-hyperpod${NC}"
    fi

    # Clear env_vars from previous runs
    > env_vars

    echo -e "${YELLOW}Generating new environment variables...${NC}"
    bash create_config.sh
    source env_vars
    echo -e "${GREEN}✅ New environment variables generated and sourced${NC}"

    echo -e "\n${BLUE}=== Environment Variables Summary ===${NC}"
    echo -e "${YELLOW}Note: You may ignore the INSTANCES parameter for now${NC}"
    echo -e "${GREEN}Current environment variables:${NC}"
    cat env_vars

    echo -e "\n${BLUE}=== Environment Setup Complete ===${NC}"
}

# Function to setup lifecycle scripts
setup_lifecycle_scripts() {
    echo -e "${BLUE}=== Setting Up Lifecycle Scripts ===${NC}"
    echo -e "${GREEN}Cloning Lifecycle Scripts${NC}"

    REPO_NAME="awsome-distributed-training"
    if [ -d "$REPO_NAME" ]; then
        echo -e "${YELLOW}⚠️  The directory '$REPO_NAME' already exists.${NC}"
        echo -e "${GREEN}Do you want to remove it and clone again? (yes/no): ${NC}"
        read -e REMOVE_AND_CLONE
        if [[ $REMOVE_AND_CLONE == "yes" ]]; then
            echo -e "${YELLOW}Removing existing directory...${NC}"
            rm -rf "$REPO_NAME"
            echo -e "${BLUE}Cloning repository...${NC}"
            git clone --depth=1 https://github.com/aws-samples/awsome-distributed-training/
            echo -e "${GREEN}✅ Repository cloned successfully${NC}"
        else
            echo -e "${BLUE}Using existing directory...${NC}"
        fi
    else
        echo -e "${BLUE}Cloning repository $REPO_NAME...${NC}"
        git clone --depth=1 https://github.com/aws-samples/awsome-distributed-training/
        echo -e "${GREEN}✅ Repository cloned successfully${NC}"
    fi

    cd awsome-distributed-training/1.architectures/5.sagemaker-hyperpod/LifecycleScripts/

    echo -e "${YELLOW}Did you deploy the optional hyperpod-observability CloudFormation stack? (yes/no)${NC}"
    read -e DEPLOYED_OBSERVABILITY

    if [ "$DEPLOYED_OBSERVABILITY" == "yes" ]; then
        echo -e "${BLUE}Enabling observability in LCS...${NC}"
        sed -i.bak 's/enable_observability = False/enable_observability = True/' base-config/config.py
        rm base-config/config.py.bak
        echo -e "${GREEN}✅ Observability enabled in configuration${NC}"

        echo -e "${BLUE}Attaching IAM policies for observability to $ROLENAME${NC}"
        aws iam attach-role-policy --role-name $ROLENAME --policy-arn arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess
        aws iam attach-role-policy --role-name $ROLENAME --policy-arn arn:aws:iam::aws:policy/AWSCloudFormationReadOnlyAccess        
        echo -e "${GREEN}✅ IAM policies attached successfully${NC}"

        echo -e "${GREEN}✅ Observability setup complete!${NC}"
    else
        echo -e "${YELLOW}Observability not enabled. Continuing with default configuration${NC}"
    fi

    echo -e "${BLUE}Uploading your lifecycle scripts to S3 bucket ${YELLOW}${BUCKET}${NC}"
    # upload data
    aws s3 cp --recursive base-config/ s3://${BUCKET}/src
    # move back to env_var directory
    cd ../../../..

    echo -e "\n${BLUE}=== Lifecycle Scripts Setup Complete ===${NC}"
}

# Helper function to get user inputs with default values specified
get_input() {
    local prompt="$1"
    local default="$2"
    local input
    read -e -p "$prompt [$default]: " input
    echo "${input:-$default}"    
}

# Function to write the cluster-config.json file
create_config() {
    echo -e "\n${BLUE}=== Lifecycle Scripts Setup Complete ===${NC}"

    # Get controller machine details
    CONTROLLER_NAME=$(get_input "Enter the name for the controller instance group" "controller-machine")
    CONTROLLER_TYPE=$(get_input "Enter the instance type for the controller" "ml.m5.12xlarge")

    # Initialize instance groups array
    INSTANCE_GROUPS="[
        {
            \"InstanceGroupName\": \"$CONTROLLER_NAME\",
            \"InstanceType\": \"$CONTROLLER_TYPE\",
            \"InstanceStorageConfigs\": [
                {
                    \"EbsVolumeConfig\": {
                        \"VolumeSizeInGB\": 500
                    }
                }
            ],
            \"InstanceCount\": 1,
            \"LifeCycleConfig\": {
                \"SourceS3Uri\": \"s3://${BUCKET}/src\",
                \"OnCreate\": \"on_create.sh\"
            },
            \"ExecutionRole\": \"${ROLE}\",
            \"ThreadsPerCore\": 2
        }"

    # Loop to add worker instance groups
    WORKER_GROUP_COUNT=1
    echo -e "\n${BLUE}=== Worker Group Configuration ===${NC}"
    while true; do
        if [[ $WORKER_GROUP_COUNT -eq 1 ]]; then
            echo -e "${GREEN}Do you want to add a worker instance group? (yes/no): ${NC}"
        else
            echo -e "${GREEN}Do you want to add another worker instance group? (yes/no): ${NC}"
        fi
        read -e ADD_WORKER
        if [[ $ADD_WORKER != "yes" ]]; then
            break
        fi

        echo -e "${YELLOW}Configuring Worker Group $WORKER_GROUP_COUNT${NC}"
        INSTANCE_TYPE=$(get_input "Enter the instance type for worker group $WORKER_GROUP_COUNT" "ml.p5.48xlarge")
        INSTANCE_COUNT=$(get_input "Enter the instance count for worker group $WORKER_GROUP_COUNT" "1")
        
        INSTANCE_GROUPS+=",
        {
            \"InstanceGroupName\": \"worker-group-$WORKER_GROUP_COUNT\",
            \"InstanceType\": \"$INSTANCE_TYPE\",
            \"InstanceCount\": $INSTANCE_COUNT,
            \"InstanceStorageConfigs\": [
                {
                    \"EbsVolumeConfig\": {
                        \"VolumeSizeInGB\": 500
                    }
                }
            ],
            \"LifeCycleConfig\": {
                \"SourceS3Uri\": \"s3://${BUCKET}/src\",
                \"OnCreate\": \"on_create.sh\"
            },
            \"ExecutionRole\": \"${ROLE}\",
            \"ThreadsPerCore\": 1"

        # MORE COMING HERE RIV 2024!!! STAY TUNED :)

        INSTANCE_GROUPS+="
        }"  

        echo -e "${GREEN}✅ Worker Group $WORKER_GROUP_COUNT added${NC}"      
        ((WORKER_GROUP_COUNT++))
    done         

    INSTANCE_GROUPS+="]"

    # Create the cluster-config.json file
    cat > cluster-config.json << EOL
    {
        "ClusterName": "ml-cluster",
        "InstanceGroups": $INSTANCE_GROUPS,
        "VpcConfig": {
        "SecurityGroupIds": ["$SECURITY_GROUP"],
        "Subnets":["$SUBNET_ID"]
        }
    }
EOL

    echo -e "${GREEN}✅ cluster-config.json created successfully${NC}"

    echo -e "\n${YELLOW}Creating provisioning_parameters.json...${NC}"
    WORKER_GROUPS="["

    # Loop through worker groups
    for ((i=1; i<=WORKER_GROUP_COUNT-1; i++)); do
        if [ $i -gt 1 ]; then
            WORKER_GROUPS+=","
        fi

        echo "$INSTANCE_GROUPS" > debug_json.txt 

        instance_type=$(jq -r ".InstanceGroups[] | select(.InstanceGroupName == \"worker-group-$i\").InstanceType" cluster-config.json)

        WORKER_GROUPS+="
            {
                \"instance_group_name\": \"worker-group-$i\",
                \"partition_name\": \"$instance_type\"
            }"
    done

    WORKER_GROUPS+="
        ]"

    cat > provisioning_parameters.json << EOL
    {
        "version": "1.0.0",
        "workload_manager": "slurm",
        "controller_group": "$CONTROLLER_NAME",
        "worker_groups": $WORKER_GROUPS,
        "fsx_dns_name": "${FSX_ID}.fsx.${AWS_REGION}.amazonaws.com",
        "fsx_mountname": "${FSX_MOUNTNAME}"
    }
EOL

    echo -e "${GREEN}✅ provisioning_parameters.json created successfully${NC}"

    # copy to the S3 Bucket
    echo -e "\n${BLUE}Copying configuration to S3 bucket...${NC}"
    aws s3 cp provisioning_parameters.json s3://${BUCKET}/src/
    echo -e "${GREEN}✅ Configuration copied to S3 bucket${NC}"

    echo -e "\n${BLUE}=== Cluster Configuration Complete ===${NC}"
}

validate_cluster_config() {
    echo "Validating your cluster configuration..."
    # TODO: MAKE SURE PACKAGES ARE INSTALLED HERE!!

    curl -O https://raw.githubusercontent.com/aws-samples/awsome-distributed-training/main/1.architectures/5.sagemaker-hyperpod/validate-config.py

    # check config for known issues
    python3 validate-config.py --cluster-config cluster-config.json --provisioning-parameters provisioning_parameters.json
}

# Function to display the prerequisites before starting this workshop
display_important_prereqs() {
    echo -e "${BLUE}Before running this script, please ensure the following:${NC}\n"

    echo -e "${GREEN}1. 🔑 IAM Credentials:${NC}"
    echo "   You have Administrator Access Credentials in IAM."
    echo "   This is crucial as we'll be using CloudFormation to create IAM roles and policies."
    echo "   Run 'aws configure' to set up your credentials."

    echo -e "\n${GREEN}2. 🌐 VPC Stack:${NC}"
    echo "   Deploy the sagemaker-hyperpod VPC stack using:"
    echo "   https://catalog.workshops.aws/sagemaker-hyperpod/en-US/00-setup/02-own-account"
    echo "   This creates essential resources: VPC, subnets, FSx Lustre volumes,"
    echo "   S3 bucket, and IAM role for your SageMaker HyperPod cluster."

    echo -e "\n${GREEN}3. 📊 Observability Stack:${NC}"
    echo "   It's highly recommended to deploy the observability stack as well."

    echo -e "\n${GREEN}4. 💻 Development Environment:${NC}"
    echo "   Ensure you have a Linux-based development environment (macOS works great too)."

    echo -e "\n${GREEN}5. 🔧 Packages required for this script to run:${NC}"
    echo "   Ensure you install the following: pip, jq, boto3."

    echo -e "\n${YELLOW}Ready to proceed? Press Enter to continue or Ctrl+C to exit...${NC}"
    read
}

region_check() {
    echo -e "${BLUE}Please confirm that your AWS region is ${GREEN}$AWS_REGION${BLUE} (default).${NC}"
    echo -e "${BLUE}If not, enter the AWS region where you want to set up your cluster (e.g., us-west-2):${NC}"
    
    read -p "> " NEW_REGION

    if [[ -z "$NEW_REGION" ]]; then
        echo -e "${GREEN}✅ Using default region: ${YELLOW}$AWS_REGION${NC}"
    else
        export AWS_REGION="$NEW_REGION"
        echo -e "${GREEN}✅ Region updated to: ${YELLOW}$AWS_REGION${NC}"
    fi    

    echo -e "\n${BLUE}Your region is set to: ${YELLOW}$AWS_REGION${NC}"
    echo -e "${BLUE}Ensure your chosen region supports SageMaker HyperPod.${NC}"
    echo -e "${BLUE}Press Enter to continue...${NC}"
    read
}


#===Main Script===
main() {
    print_header "🚀 Welcome to the SageMaker HyperPod Cluster Creation Script! 🚀"

    # Prerequisites
    display_important_prereqs

    # Checking AWS Account ID
    echo -e "\n${BLUE}🔍 AWS Account Verification${NC}"
    echo -e "Your AWS Account ID is: ${GREEN}$AWS_ACCOUNT_ID${NC}"
    echo "Press Enter to confirm ✅ or Ctrl+C to exit❌..."
    read

    # Checking Git installation
    check_git

    # Checking AWS CLI version and installation
    echo -e "\n${BLUE}📦 1a: AWS CLI Installation and Verification${NC}"
    check_and_install_aws_cli

    # Checking Region
    echo -e "\n${BLUE}🌎 AWS Region Configuration${NC}"
    region_check

    # Lifecycle Scripts Setup
    echo -e "\n${BLUE}🔧 Setting Up Lifecycle Scripts${NC}"
    echo -e "${BLUE}1b. Configuring environment variables and lifecycle scripts...${NC}"
    setup_env_vars
    setup_lifecycle_scripts
    echo -e "${GREEN}✅ Lifecycle scripts setup completed${NC}"


    # Cluster Configuration
    echo -e "\n${BLUE}🚀 Creating the Cluster${NC}"
    echo -e "${BLUE}1c. Generating cluster configuration...${NC}"
    create_config
    echo -e "${GREEN}✅ Cluster configuration created successfully${NC}"
    echo -e "${BLUE}ℹ️  Validating the generated configuration before proceeding${NC}"
    validate_cluster_config
    echo -e "${BLUE}ℹ️  For your viewing, here's the cluster configuration generated. Please make sure it looks right before proceeding. Press enter to continue, or Ctrl+C to exit and make changes${NC}"
    echo -e "${YELLOW}$(cat cluster-config.json | jq . --color-output)${NC}"
    read

    print_header "🎉 Cluster Creation Script Completed! 🎉"

    # Instructions for next steps
    echo -e "${GREEN}Congratulations! You've completed all the preparatory steps.${NC}"
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "${YELLOW}Run the following command to create the cluster. Exiting this script!${NC}"

    # Command to create the cluster
    echo -e "${YELLOW}aws sagemaker create-cluster \\"
    echo -e "${YELLOW}    --cli-input-json file://cluster-config.json \\"
    echo -e "${YELLOW}    --region $AWS_REGION${NC}\n"

    # Warning message
    echo -e "${BLUE}⚠️  Please note:${NC}"
    echo -e "   - Cluster creation may take some time (~15-20 min)"
    echo -e "   - This operation may incur costs on your AWS account"
    echo -e "   - Ensure you understand the implications before proceeding\n"

    # Final goodbye message
    echo -e "${GREEN}Thank you for using the SageMaker HyperPod Cluster Creation Script!${NC}"
    echo -e "${GREEN}For any issues or questions, please refer to the AWS documentation.${NC}"
    echo "https://docs.aws.amazon.com/sagemaker/latest/dg/smcluster-getting-started.html"

    # Exit message
    echo -e "\n${BLUE}Exiting script. Good luck with your SageMaker HyperPod journey! 👋${NC}\n"
}

main
