#!/bin/bash

# Workshop Automation Script
# This script automates the steps of the workshop by executing CLI commands

# Exit immediately if a command exits with a non-zero status. Print commands and their arguments as executed
set -e

#===Global===
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export AWS_REGION=${AWS_DEFAULT_REGION:-$(aws configure get region)}
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

clone_adt() {
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
}

# Function to setup environment variables
setup_env_vars() {
    echo -e "${BLUE}=== Setting Up Environment Variables ===${NC}"
    echo -e "${GREEN}Cloning awsome-distributed-training${NC}"
    clone_adt

    echo -e "${BLUE}Enter the name of the SageMaker VPC CloudFormation stack that was deployed as a prerequisite (default: sagemaker-hyperpod):${NC}"
    read -e STACK_ID_VPC
    export STACK_ID_VPC=${STACK_ID_VPC:-sagemaker-hyperpod}

    if [ "$CF_STACK_NAME" != "sagemaker-hyperpod" ]; then
        echo -e "${GREEN}✅ Configuration script updated with stack name: $STACK_ID_VPC${NC}"
    else
        echo -e "${GREEN}Using default stack name: sagemaker-hyperpod${NC}"
    fi

    # Clear env_vars from previous runs
    > env_vars

    echo -e "${YELLOW}Generating new environment variables...${NC}"
    
    generate_env_vars() {
        bash awsome-distributed-training/1.architectures/5.sagemaker-hyperpod/create_config.sh
        # bash create_config.sh
    }

    # Capture stdout + stderr
    if error_output=$(generate_env_vars 2>&1); then
        echo -e "${GREEN}✅ New environment variables generated and sourced${NC}"
    else
        echo -e "${YELLOW}⚠️  Error occurred while generating environment variables:${NC}"
        echo -e "${YELLOW}$error_output${NC}"
        echo -e "Options:"
        echo -e "1. Press Enter to continue with the rest of the script (Not Recommended, unless you know how to set the environment variables manually!)"
        echo -e "2. Press Ctrl+C to exit the script."

        read -e -p "Select an option (Enter/Ctrl+C): " choice

        if [[ -z "$choice" ]]; then
            echo -e "${BLUE}Continuing with the rest of the script...${NC}"
        fi
    fi    

    source env_vars

    echo -e "\n${BLUE}=== Environment Variables Summary ===${NC}"
    echo -e "${YELLOW}Note: You may ignore the INSTANCES parameter for now${NC}"
    echo -e "${GREEN}Current environment variables:${NC}"
    cat env_vars

    echo -e "\n${BLUE}=== Environment Setup Complete ===${NC}"
}

# Function to setup lifecycle scripts
setup_lifecycle_scripts() {
    echo -e "${BLUE}=== Setting Up Lifecycle Scripts ===${NC}"

    cd awsome-distributed-training/1.architectures/5.sagemaker-hyperpod/LifecycleScripts/

    echo -e "${YELLOW}Did you deploy the optional hyperpod-observability CloudFormation stack? (yes/no)${NC}"
    read -e DEPLOYED_OBSERVABILITY

    if [ "$DEPLOYED_OBSERVABILITY" == "yes" ]; then
        echo -e "${BLUE}Enabling observability in LCS...${NC}"
        sed -i.bak 's/enable_observability = False/enable_observability = True/' base-config/config.py
        rm base-config/config.py.bak
        echo -e "${GREEN}✅ Lifecycle Scripts modified successfully! Observability enabled in config.py${NC}"

        echo -e "${BLUE}Attaching IAM policies for observability to $ROLENAME${NC}"

        # Helper function for attaching IAM policies (specific to observability stack only!)
        attach_policies() {
            aws iam attach-role-policy --role-name $ROLENAME --policy-arn arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess --output json
            aws iam attach-role-policy --role-name $ROLENAME --policy-arn arn:aws:iam::aws:policy/AWSCloudFormationReadOnlyAccess --output json
        }

        # Capture stdout + stderr

        if ! error_output=$(attach_policies 2>&1); then
            echo -e "${YELLOW}⚠️  Failed to attach IAM policies. This operation requires admin permissions${NC}"
            echo -e "${YELLOW}   This was the error received${NC}"
            echo -e "${YELLOW}$error_output${NC}"
            echo -e "Options:"
            echo -e "1. Run 'aws configure' as an admin user as part of this script."
            echo -e "2. Press Ctrl+C to exit and run 'aws configure' as an admin user outside this script."
            echo -e "3. Press Enter to continue with the rest of the script without configuring this step."

            read -e -p "Choose an option (1, 2, or 3): " choice   
            
            case $choice in
                1)
                    echo -e "${BLUE}Running 'aws configure'. Please enter your **admin** credentials..${NC}"
                    aws configure
                    echo -e "${GREEN}✅ AWS CLI configured successfully${NC}"
                    echo -e "${BLUE}Retrying to attach IAM policies!${NC}"
                    if ! attach_policies; then
                        echo -e "${YELLOW}⚠️  Failed to attach IAM policies. Please attach the following policies manually:${NC}"
                        echo -e "1. AmazonPrometheusRemoteWriteAccess"
                        echo -e "2. AWSCloudFormationReadOnlyAccess"
                        echo -e "Press Enter to continue with the rest of the script without configuring this step."
                        read -e -p "Press Enter to continue: "
                        echo -e "${BLUE}Continuing with the rest of the script without configuring this step.${NC}"
                    else
                        echo -e "${GREEN}✅ IAM policies attached successfully${NC}"
                    fi
                    ;;
                2)
                    echo -e "${BLUE}Please run 'aws configure' as an admin user outside this script.${NC}"
                    exit 1
                    ;;
                3)
                    echo -e "${BLUE}Continuing with the rest of the script without configuring this step.${NC}"
                    ;;
                *)
                    echo -e "${BLUE}Invalid choice. Continuing with the rest of the script without configuring this step.${NC}"
                    ;;
            esac
        else
            echo -e "${GREEN}✅ IAM policies attached successfully${NC}"
        fi    
        echo -e "${GREEN}✅ Observability setup complete!${NC}"
    else
        echo -e "${YELLOW}Observability not enabled. Continuing with default configuration${NC}"
    fi

    echo -e "${BLUE}Uploading your lifecycle scripts to S3 bucket ${YELLOW}${BUCKET}${NC}"
    # upload data
    upload_to_s3() {
        aws s3 cp --recursive base-config/ s3://${BUCKET}/src --output json
    }

    if error_output=$(upload_to_s3 2>&1); then
        echo -e "${GREEN}✅ Lifecycle scripts uploaded successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Error occurred while uploading lifecycle scripts to S3 bucket:${NC}"
        echo -e "${YELLOW}$error_output${NC}"
        echo -e "Options:"
        echo -e "1. Press Enter to continue with the rest of the script (Not Recommended, unless you know how to set the environment variables manually!)"
        echo -e "2. Press Ctrl+C to exit the script."

        read -e -p "Select an option (Enter/Ctrl+C): " choice

        if [[ -z "$choice" ]]; then
            echo -e "${BLUE}Continuing with the rest of the script...${NC}"
        else
            exit 1
        fi
    fi  

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
    INSTANCE_GROUPS="["

    # Add login group
    echo -e "${GREEN}Do you want to add a login group? (yes/no): ${NC}"
    read -e ADD_LOGIN_GROUP

    if [[ $ADD_LOGIN_GROUP == "yes" ]]; then
        LOGIN_TYPE=$(get_input "Enter the instance type for the login group" "ml.m5.4xlarge")

        INSTANCE_GROUPS+="{
            \"InstanceGroupName\": \"login-group\",
            \"InstanceType\": \"$LOGIN_TYPE\",
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
        },"
        
        echo -e "${GREEN}✅ Login Group added${NC}"
    fi

    # Add controller group
    INSTANCE_GROUPS+="{
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
            ADD_WORKER=$(get_input "Do you want to add a worker instance group? (yes/no):" "yes")
        else
            ADD_WORKER=$(get_input "Do you want to add another worker instance group? (yes/no):" "no")
        fi

        if [[ $ADD_WORKER != "yes" ]]; then
            break
        fi

        echo -e "${YELLOW}Configuring Worker Group $WORKER_GROUP_COUNT${NC}"
        INSTANCE_TYPE=$(get_input "Enter the instance type for worker group $WORKER_GROUP_COUNT" "ml.c5.4xlarge")
        INSTANCE_COUNT=$(get_input "Enter the instance count for worker group $WORKER_GROUP_COUNT" "4")
        
        echo -e "${GREEN}Are you using training plans? (yes/no): ${NC}"
        read -e USE_TRAINING_PLAN

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

        if [[ $USE_TRAINING_PLAN == "yes" ]]; then
            echo -e "\n${BLUE}=== Training Plan Configuration ===${NC}"
            # aws iam attach-role-policy --role-name $ROLENAME --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

            TRAINING_PLAN=$(get_input "Enter the training plan name" "")

            count=0
            while true; do
                # Attempt to describe the training plan
                echo -e "${YELLOW}Attempting to retrieve training plan details...${NC}"
                
                if ! TRAINING_PLAN_DESCRIPTION=$(aws sagemaker describe-training-plan --training-plan-name "$TRAINING_PLAN" --output json 2>&1); then
                    echo -e "${BLUE}❌Error: Training plan '$TRAINING_PLAN' not found. Please try again.${NC}"
                    echo -e "${GREEN}Are you using training plans (Beta feature)? (yes/no)${NC}"
                    read -e USE_TRAINING_PLAN
                    if [[ $USE_TRAINING_PLAN != "yes" ]]; then
                        echo -e "${YELLOW}Exiting training plan configuration.${NC}"
                        break
                    else
                        TRAINING_PLAN=$(get_input "Enter the training plan name" "")   
                    fi
                else
                    # Extract relevant information from the description
                    TRAINING_PLAN_ARN=$(echo "$TRAINING_PLAN_DESCRIPTION" | jq -r '.TrainingPlanArn')
                    AVAILABLE_INSTANCE_COUNT=$(echo "$TRAINING_PLAN_DESCRIPTION" | jq -r '.AvailableInstanceCount')
                    TOTAL_INSTANCE_COUNT=$(echo "$TRAINING_PLAN_DESCRIPTION" | jq -r '.TotalInstanceCount')
                    TRAINING_PLAN_AZ=$(echo "$TRAINING_PLAN_DESCRIPTION" | jq -r '.ReservedCapacitySummaries[0].AvailabilityZone')
                    TP_INSTANCE_TYPE=$(echo "$TRAINING_PLAN_DESCRIPTION" | jq -r '.ReservedCapacitySummaries[0].InstanceType')

                    CF_AZ=$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID --output json | jq -r '.Subnets[0].AvailabilityZone')

                    # Only print if count=0
                    if [[ $count -eq 0 ]]; then
                        echo -e "${GREEN}Training Plan Details:${NC}"
                        echo -e "  ${YELLOW}Name:${NC} $TRAINING_PLAN"
                        echo -e "  ${YELLOW}Available Instance Count:${NC} $AVAILABLE_INSTANCE_COUNT"
                        echo -e "  ${YELLOW}Total Instance Count:${NC} $TOTAL_INSTANCE_COUNT"
                        echo -e "  ${YELLOW}Training Plan Availability Zone:${NC} $TRAINING_PLAN_AZ"
                        echo -e "  ${YELLOW}Training Plan Instance Type:${NC} $TP_INSTANCE_TYPE"
                    fi

                    # Compare INSTANCE_COUNT with AVAILABLE_INSTANCE_COUNT
                    INSTANCE_COUNT_OK="n"
                    if [[ $INSTANCE_COUNT -gt $AVAILABLE_INSTANCE_COUNT ]]; then
                        echo -e "${YELLOW}Warning: The requested instance count ($INSTANCE_COUNT) is greater than the available instances in the training plan ($AVAILABLE_INSTANCE_COUNT).${NC}"
                        echo -e "${BLUE}Do you want to continue anyway?(yes/no)${NC}"
                        read -e CONTINUE
                        if [[ $CONTINUE != "yes" ]]; then
                            NEW_INSTANCE_COUNT=$(get_input "Enter the new number of instances" "1")
                            # Update INSTANCE_GROUPS with new INSTANCE_COUNT for the current worker group
                            INSTANCE_GROUPS=$(echo "$INSTANCE_GROUPS" | perl -pe '
                                BEGIN {
                                    $group = "worker-group-'"$WORKER_GROUP_COUNT"'";
                                    $count = '"$NEW_INSTANCE_COUNT"';
                                    $in_group = 0;
                                }
                                if (/"InstanceGroupName":\s*"$group"/) {
                                    $in_group = 1;
                                }
                                if ($in_group && /"InstanceCount":\s*\d+/) {
                                    s/("InstanceCount":\s*)\d+/$1$count/;
                                    $in_group = 0;
                                }
                            ')
                            INSTANCE_COUNT=$NEW_INSTANCE_COUNT
                            echo -e "${GREEN}Updated instance count for worker-group-$WORKER_GROUP_COUNT to $INSTANCE_COUNT${NC}"
                        fi
                        INSTANCE_COUNT_OK="y"
                    else
                        INSTANCE_COUNT_OK="y"    
                    fi

                    if [[ $INSTANCE_COUNT_OK == "y" ]]; then
                        INSTANCE_TYPE_OK="n"
                        # Compare INSTANCE_TYPE with TP_INSTANCE_TYPE
                        if [[ $INSTANCE_TYPE != $TP_INSTANCE_TYPE ]]; then
                            echo -e "${YELLOW}Warning: The requested instance type ($INSTANCE_TYPE) does not match the instance type in the training plan ($TP_INSTANCE_TYPE).${NC}"
                            echo -e "${BLUE}Do you want to continue anyway? If you choose "no", then the script will update instance type for you and proceed. (yes/no)${NC}"
                            read -e CONTINUE
                            if [[ $CONTINUE != "yes" ]]; then
                                NEW_INSTANCE_TYPE=$TP_INSTANCE_TYPE
                                # Update INSTANCE_GROUPS with new INSTANCE_TYPE for the current worker group
                                INSTANCE_GROUPS=$(echo "$INSTANCE_GROUPS" | perl -pe '
                                    BEGIN {
                                        $group = "worker-group-'$WORKER_GROUP_COUNT'";
                                        $type = "'$NEW_INSTANCE_TYPE'";
                                        $in_group = 0;
                                    }
                                    if (/"InstanceGroupName":\s*"$group"/) {
                                        $in_group = 1;
                                    }
                                    if ($in_group && /"InstanceType":\s*"[^"]*"/) {
                                        s/("InstanceType":\s*")[^"]*"/$1$type"/;
                                        $in_group = 0;
                                    }
                                ')
                                INSTANCE_TYPE=$NEW_INSTANCE_TYPE
                                echo -e "${GREEN}Updated instance type for worker-group-$WORKER_GROUP_COUNT to $INSTANCE_TYPE${NC}"
                            fi
                            INSTANCE_TYPE_OK="y"
                        else
                            INSTANCE_TYPE_OK="y"    
                        fi       

                        if [[ $INSTANCE_TYPE_OK == "y" ]]; then
                            # Compare TRAINING_PLAN_AZ with CF_AZ
                            if [[ $TRAINING_PLAN_AZ != $CF_AZ ]]; then
                                echo -e "${YELLOW}Warning: The training plan availability zone ($TRAINING_PLAN_AZ) does not match the cluster availability zone ($CF_AZ).${NC}"
                                echo -e "${BLUE}Do you want to continue anyway? (yes/no)${NC}"
                                read -e CONTINUE
                                if [[ $CONTINUE != "yes" ]]; then
                                    echo -e "${YELLOW}Please ensure that your VPC is in the same Availability Zone as your training plan (or vice versa). If you used the workshop, this should be the CF stack \"sagemaker-hyperpod\". Exiting training plan configuration.${NC}"
                                    continue
                                fi
                            fi
                        fi  
                    fi   

                    echo -e "${GREEN}Adding Training Plan ARN to instance group configuration.${NC}"    
                    INSTANCE_GROUPS+=",
                    \"TrainingPlanArn\": \"$TRAINING_PLAN_ARN\""  
                    break
                fi
                count+=1
            done       
        fi  

        INSTANCE_GROUPS+="
        }"  

        echo -e "${GREEN}✅ Worker Group $WORKER_GROUP_COUNT added${NC}"      
        ((WORKER_GROUP_COUNT++))
    done         

    INSTANCE_GROUPS+="]"

    read -e -p "What would you like to name your cluster? (default: ml-cluster): " CLUSTER_NAME
    CLUSTER_NAME=${CLUSTER_NAME:-ml-cluster}

    # Create the cluster-config.json file
    cat > cluster-config.json << EOL
    {
        "ClusterName": "$CLUSTER_NAME",
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

        instance_type=$(jq -r ".InstanceGroups[] | select(.InstanceGroupName == \"worker-group-$i\").InstanceType" cluster-config.json)

        WORKER_GROUPS+="
            {
                \"instance_group_name\": \"worker-group-$i\",
                \"partition_name\": \"$instance_type\"
            }"
    done

    WORKER_GROUPS+="
        ]"

    if [[ $ADD_LOGIN_GROUP == "yes" ]]; then    
        cat > provisioning_parameters.json << EOL
        {
            "version": "1.0.0",
            "workload_manager": "slurm",
            "controller_group": "$CONTROLLER_NAME",
            "login_group": "login-group",
            "worker_groups": $WORKER_GROUPS,
            "fsx_dns_name": "${FSX_ID}.fsx.${AWS_REGION}.amazonaws.com",
            "fsx_mountname": "${FSX_MOUNTNAME}"
        }
EOL
    else
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
    fi
    
    echo -e "${GREEN}✅ provisioning_parameters.json created successfully${NC}"

    # copy to the S3 Bucket
    echo -e "\n${BLUE}Copying configuration to S3 bucket...${NC}"

    # upload data
    upload_to_s3() {
        aws s3 cp provisioning_parameters.json s3://${BUCKET}/src/ --output json
    }

    if error_output=$(upload_to_s3 2>&1); then
        echo -e "${GREEN}✅ Provisioning Parameters uploaded successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Error occurred while uploading lifecycle scripts to S3 bucket:${NC}"
        echo -e "${YELLOW}$error_output${NC}"
        echo -e "Options:"
        echo -e "1. Press Enter to continue with the rest of the script (Not Recommended)"
        echo -e "2. Press Ctrl+C to exit the script."

        read -e -p "Select an option (Enter/Ctrl+C): " choice

        if [[ -z "$choice" ]]; then
            echo -e "${BLUE}Continuing with the rest of the script...${NC}"
        else
            exit 1
        fi
    fi    

    echo -e "\n${BLUE}=== Cluster Configuration Complete ===${NC}"
}

validate_cluster_config() {
    echo "Validating your cluster configuration..."
    # TODO: MAKE SURE PACKAGES ARE INSTALLED HERE!!

    curl -O https://raw.githubusercontent.com/aws-samples/awsome-distributed-training/main/1.architectures/5.sagemaker-hyperpod/validate-config.py

    # check config for known issues
    python3 validate-config.py --cluster-config cluster-config.json --provisioning-parameters provisioning_parameters.json --region $AWS_REGION
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
    echo "   Navigate to https://catalog.workshops.aws/sagemaker-hyperpod/en-US/00-setup/02-own-account#2.-deploy-cluster-observability-stack-(recommended) to deploy the stack"

    echo -e "\n${GREEN}4. 💻 Development Environment:${NC}"
    echo "   Ensure you have a Linux-based development environment (macOS works great too)."

    echo -e "\n${GREEN}5. 🔧 Packages required for this script to run:${NC}"
    echo "   Ensure you install the following: pip, jq, boto3, and jsonschema"

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
    echo -e "${GREEN}You can check out https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod.html#sagemaker-hyperpod-available-regions to learn about supported regions.${NC}"
    echo -e "${BLUE}Press Enter to continue...${NC}"
    read
}

# Function to create the cluster
create_cluster() {
    echo -e "${GREEN}✅ Creating cluster for you!${NC}"

    if ! output=$(aws sagemaker create-cluster \
        --cli-input-json file://cluster-config.json \
        --region $AWS_REGION \
        --output json 2>&1); then

        echo -e "${YELLOW}⚠️  Error occurred while creating the cluster:${NC}"
        echo -e "${YELLOW}$output${NC}"

        echo -e "Options:"
        echo -e "1. Press Enter to continue with the rest of the script (you will run the command below yourself!)"
        echo -e "2. Press Ctrl+C to exit the script."

        # Command to create the cluster
        echo -e "${GREEN} aws sagemaker create-cluster \\"
        echo -e "${GREEN}    --cli-input-json file://cluster-config.json \\"
        echo -e "${GREEN}    --region $AWS_REGION --output json${NC}\n"

        read -e -p "Select an option (Enter/Ctrl+C): " choice

        if [[ -z "$choice" ]]; then
            echo -e "${BLUE}Continuing with the rest of the script...${NC}"
        else
            exit 1
        fi
    else
        echo -e "${GREEN}✅ Cluster creation request submitted successfully. To monitor the progress of cluster creation, you can either check the SageMaker console, or you can run:.${NC}"    
        echo -e "${YELLOW}watch -n 1 aws sagemaker list-clusters --output table${NC}"
    fi
}

# Warning message function
warning() {
    echo -e "${BLUE}⚠️  Please note:${NC}"
    echo -e "   - Cluster creation may take some time (~15-20 min)"
    echo -e "   - This operation may incur costs on your AWS account"
    echo -e "   - Ensure you understand the implications before proceeding\n"
}

# Function to display goodbye message
goodbye() {
    # Final goodbye message
    echo -e "${GREEN}Thank you for using the SageMaker HyperPod Cluster Creation Script!${NC}"
    echo -e "${GREEN}For any issues or questions, please refer to the AWS documentation.${NC}"
    echo "https://docs.aws.amazon.com/sagemaker/latest/dg/smcluster-getting-started.html"

    # Exit message
    echo -e "\n${BLUE}Exiting script. Good luck with your SageMaker HyperPod journey! 👋${NC}\n"
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

    if error_output=$(validate_cluster_config 2>&1); then
        echo -e "${GREEN}✅ Cluster configuration validated!${NC}"
    else
        echo -e "${YELLOW}⚠️  Error occurred while validating cluster config script:${NC}"
        echo -e "${YELLOW}$error_output${NC}"
        echo -e "Options:"
        echo -e "1. Press Enter to continue with the rest of the script (Not Recommended, unless you know how to set the environment variables manually!)"
        echo -e "2. Press Ctrl+C to exit the script."

        read -e -p "Select an option (Enter/Ctrl+C): " choice

        if [[ -z "$choice" ]]; then
            echo -e "${BLUE}Continuing with the rest of the script...${NC}"
        else
            exit 1
        fi
    fi  

    
    echo -e "${BLUE}ℹ️  For your viewing, here's the cluster configuration generated. Please make sure it looks right before proceeding. Press enter to continue, or Ctrl+C to exit and make changes${NC}"
    echo -e "${YELLOW}$(cat cluster-config.json | jq . --color-output)${NC}"
    read

    print_header "🎉 Cluster Creation Script Completed! 🎉"

    # Instructions for next steps
    echo -e "${GREEN}Congratulations! You've completed all the preparatory steps.${NC}"
    echo -e "${YELLOW}Next Steps:${NC}"

    CREATE_CLUSTER=$(get_input "Do you want the script to create the cluster for you now? (yes/no):" "yes")
    # read -e -p "Do you want the script to create the cluster for you now? (yes/no): " CREATE_CLUSTER
    if [[ "$CREATE_CLUSTER" == "yes" ]]; then
        warning
        create_cluster
        goodbye
    else
        echo -e "${YELLOW}Run the following command to create the cluster. Exiting this script!${NC}"

        # Command to create the cluster
        echo -e "${GREEN} aws sagemaker create-cluster \\"
        echo -e "${GREEN}    --cli-input-json file://cluster-config.json \\"
        echo -e "${GREEN}    --region $AWS_REGION --output json${NC}\n"

        echo -e "${YELLOW}To monitor the progress of cluster creation, you can either check the SageMaker console, or you can run:.${NC}"    
        echo -e "${GREEN}watch -n 1 aws sagemaker list-clusters --output table${NC}"

        \
        warning
        goodbye
    fi    
}

main
