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
RED='\033[0;31m'
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

    # Clear env_vars from previous runs
    > env_vars

    echo -e "${YELLOW}Generating new environment variables...${NC}"
    
    generate_env_vars() {
        ACCEL_INSTANCE_TYPE=$INSTANCE_TYPE
        ACCEL_INSTANCE_COUNT=$INSTANCE_COUNT
        GEN_INSTANCE_TYPE=$CONTROLLER_TYPE
        GEN_INSTANCE_COUNT=$CONTROLLER_COUNT

        curl -O https://raw.githubusercontent.com/aws-samples/awsome-distributed-training/refs/heads/main/1.architectures/7.sagemaker-hyperpod-eks/create_config.sh 
        #bash awsome-distributed-training/1.architectures/5.sagemaker-hyperpod/create_config.sh
        #curl -O https://github.com/aws-samples/awsome-distributed-training/blob/feature/slinkly-slurm-hyperpod-eks/1.architectures/5.sagemaker-hyperpod/create_config.sh
        chmod +x create_config.sh
        ./create_config.sh
        #source env_vars
        bash create_config.sh
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

    # FEAT: Add support for multiple headnodes
    #MH
    #multi_headnode

    source env_vars

    echo -e "\n${BLUE}=== Environment Variables Summary ===${NC}"
    echo -e "${GREEN}Current environment variables:${NC}"
    cat env_vars
    echo -e "\n${BLUE}=== Environment Setup Complete ===${NC}"
}


# Helper function to get user inputs with default values specified
get_input() {
    local prompt="$1"
    local default="$2"
    local input
    read -e -p "$prompt [$default]: " input
    echo "${input:-$default}"    
}

deploy_cloudformation()
{
    #1. downloand the main-stack.yaml file 
    echo "downloading the CloudFormation templete file: https://raw.githubusercontent.com/aws-samples/awsome-distributed-training/refs/heads/main/1.architectures/7.sagemaker-hyperpod-eks/cfn-templates/nested-stacks/main-stack.yaml "
    curl -O https://raw.githubusercontent.com/aws-samples/awsome-distributed-training/refs/heads/main/1.architectures/7.sagemaker-hyperpod-eks/cfn-templates/nested-stacks/main-stack.yaml
    
    # Optional: Add check to verify download was successful
    if [ $? -eq 0 ]; then
        echo "Successfully downloaded main-stack.yaml"
    else
        echo "Failed to download main-stack.yaml"
        return 1
    fi

    #2.creating the stack
    aws cloudformation create-stack \
        --stack-name $STACK_ID \
        --template-body file://main-stack.yaml \
        --region $AWS_REGION \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --parameters file://cloudFormation.json

    if [ $? -eq 0 ]; then
        echo "Stack creation initiated successfully"
    else
        echo "Error creating stack"
        return 1
    fi

}


wait_for_stack_completion() {
    local stack_name=$1
    local -a spinner=('-' '\' '|' '/')
    local i=0

    echo "Waiting for stack creation to complete... "
    echo "This can take about 20 mins."
    while true; do
        STATUS=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].StackStatus' --output text)
        case $STATUS in
            CREATE_COMPLETE)
                printf "\r\033[K✅ CloudFormation stack created successfully\n"
                return 0
                ;;
            CREATE_IN_PROGRESS)
                printf "\r\033[KStack creation in progress... ${spinner[$i]}"
                i=$(( (i+1) % 4 ))
                ;;
            CREATE_FAILED|ROLLBACK_IN_PROGRESS|ROLLBACK_COMPLETE|ROLLBACK_FAILED)
                printf "\r\033[K❌ Stack creation failed with status: $STATUS\n"
                return 1
                ;;
        esac
        sleep 60
    done
}


create_cloudformation_stack() {
    region_prefix=$(echo $AWS_REGION | sed 's/us-west-/usw/;s/us-east-/use/;s/eu-west-/euw/;s/ap-south-/aps/;s/ap-northeast-/apne/;s/ap-southeast-/apse/')
    availability_zone="${region_prefix}-az2"
    cat > cloudFormation.json << EOL
[
    {
        "ParameterKey": "KubernetesVersion",
        "ParameterValue": "1.32"
    },
    {
        "ParameterKey": "EKSClusterName",
        "ParameterValue": "$EKS_CLUSTER_NAME"
    },
    {
        "ParameterKey": "HyperPodClusterName",
        "ParameterValue": "${EKS_CLUSTER_NAME}-hp"
    },
    {
        "ParameterKey": "ResourceNamePrefix",
        "ParameterValue": "${EKS_CLUSTER_NAME}-hp"
    },
    {
        "ParameterKey": "AvailabilityZoneId",    
        "ParameterValue": "$availability_zone"
    },
    {
        "ParameterKey": "AcceleratedInstanceGroupName",
        "ParameterValue": "accelerated-instance-group-1"
    },
    {
        "ParameterKey": "AcceleratedInstanceType",
        "ParameterValue": "$INSTANCE_TYPE"
    },
    {
        "ParameterKey": "AcceleratedInstanceCount",
        "ParameterValue": "$INSTANCE_COUNT"
    },
    {
        "ParameterKey": "AcceleratedEBSVolumeSize",
        "ParameterValue": "500"
    },
    {
        "ParameterKey": "AcceleratedThreadsPerCore",
        "ParameterValue": "2"
    },
    {
        "ParameterKey": "EnableInstanceStressCheck",
        "ParameterValue": "true"
    },
    {
        "ParameterKey": "EnableInstanceConnectivityCheck",
        "ParameterValue": "true"
    },
    {
        "ParameterKey": "CreateGeneralPurposeInstanceGroup",
        "ParameterValue": "true"
    },
    {
        "ParameterKey": "GeneralPurposeInstanceGroupName",
        "ParameterValue": "$CONTROLLER_NAME"
    },
    {
        "ParameterKey": "GeneralPurposeInstanceType",
        "ParameterValue": "$CONTROLLER_TYPE"
    },
    {
        "ParameterKey": "GeneralPurposeInstanceCount",
        "ParameterValue": "$CONTROLLER_COUNT"
    },
    {
        "ParameterKey": "GeneralPurposeEBSVolumeSize",
        "ParameterValue": "500"
    },
    {
        "ParameterKey": "GeneralPurposeThreadsPerCore",
        "ParameterValue": "1"
    }
]
EOL
#
    echo -e "${GREEN}✅ cloudFormation.json created successfully${NC}"
    echo -e "${BLUE}=== Deploying CloudFormation stack ===${NC}"
    if deploy_cloudformation; then
        echo -e "${GREEN}✅ CloudFormation stack deployed successfully${NC}"
    else
        echo -e "${RED}❌ CloudFormation stack deployment failed${NC}"
        exit 1
    fi

    if wait_for_stack_completion "slinky-eks-cluster"; then
        echo -e "${GREEN}✅ Stack creation completed successfully!${NC}"
        #echo -e "${GREEN}✅ Proceeding with next steps...${NC}"
        #sourcing the env vars
    else
        echo -e "${RED}❌ Stack creation failed. Exiting...${NC}"
        exit 1
    fi

}

# Function to write the cluster-config.json file
create_config() {
    #echo -e "\n${BLUE}=== Lifecycle Scripts Setup Complete ===${NC}"
    #STACK_NAME=$(get_input "enter the name of the eks cluster" "slinky-eks-cluster")
    EKS_CLUSTER_NAME=$(get_input "enter the name of the eks cluster" "slinky-eks-cluster") #eks cluster name
    STACK_ID=$EKS_CLUSTER_NAME
    # Get controller machine details
    CONTROLLER_NAME=$(get_input "Enter the name for the controller instance group" "controller-machine")
    CONTROLLER_TYPE=$(get_input "Enter the instance type for the controller" "ml.m5.2xlarge")

   

    CONTROLLER_COUNT=$([ "${MH:-false}" = true ] && echo "2" || echo "1")
    EXECUTION_ROLE=$([ "${MH:-false}" = true ] && echo "${SLURM_EXECUTION_ROLE_ARN}" || echo "${ROLE}")

    # Loop to add worker instance groups
    WORKER_GROUP_COUNT=1
    echo -e "\n${BLUE}=== Worker Group Configuration ===${NC}"
    #while true; do

    if [[ $WORKER_GROUP_COUNT -eq 1 ]]; then
        ADD_WORKER=$(get_input "Do you want to add a worker instance group? (yes/no):" "yes")
    #else
        #ADD_WORKER=$(get_input "Do you want to add another worker instance group? (yes/no):" "no")
    fi

    if [[ $ADD_WORKER != "yes" ]]; then
        break
    fi

    echo -e "${YELLOW}Configuring Worker Group $WORKER_GROUP_COUNT${NC}"
    INSTANCE_TYPE=$(get_input "Enter the instance type for worker group $WORKER_GROUP_COUNT" "ml.g5.8xlarge")
    INSTANCE_COUNT=$(get_input "Enter the instance count for worker group $WORKER_GROUP_COUNT" "4")
     
    #creating the cloud fomration stack
    create_cloudformation_stack
    #sourcing the env var
    setup_env_vars #sets and sources the env variables 

     # Initialize instance groups array
    INSTANCE_GROUPS="["
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
        \"InstanceCount\": ${CONTROLLER_COUNT},
        \"LifeCycleConfig\": {
            \"SourceS3Uri\": \"s3://${S3_BUCKET_NAME}/src\",
            \"OnCreate\": \"on_create.sh\"
        },
        \"ExecutionRole\": \"${EXECUTION_ROLE}\",
        \"ThreadsPerCore\": 1
    }"
    
    # add worker group 
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
            \"SourceS3Uri\": \"s3://${S3_BUCKET_NAME}/src\",
            \"OnCreate\": \"on_create.sh\"
        },
        \"ExecutionRole\": \"${ROLE}\",
        \"ThreadsPerCore\": 2" 

    INSTANCE_GROUPS+="
    }"  

    echo -e "${GREEN}✅ Worker Group $WORKER_GROUP_COUNT added${NC}"      
    ((WORKER_GROUP_COUNT++))
    #done         
    INSTANCE_GROUPS+="]"
    #done with the instance array 

    read -e -p "What would you like to name your cluster? (default: slinky-cluster): " CLUSTER_NAME
    CLUSTER_NAME=${CLUSTER_NAME:-slinky-cluster}

    # Create the cluster-config.json file
    cat > cluster-config.json << EOL
    {
        "ClusterName": "$CLUSTER_NAME",
        "InstanceGroups": $INSTANCE_GROUPS,
        "VpcConfig": {
        "SecurityGroupIds": ["$SECURITY_GROUP_ID"],
        "Subnets":["$PRIVATE_SUBNET_ID"]
        }
    }
EOL

}

# Function to create FSx for Lustre Storage Class
create_fsx_lustre_storage_class() 
{
    echo -e "${BLUE}=== Creating FSx for Lustre Storage Class ===${NC}"
    
    # Create an IAM OpenID Connect (OIDC) identity provider for the cluster
    echo -e "${YELLOW}Creating IAM OIDC identity provider...${NC}"
    eksctl utils associate-iam-oidc-provider --cluster $EKS_CLUSTER_NAME --approve
    
    # Create a service account with an IAM role for the FSx for Lustre CSI driver
    echo -e "${YELLOW}Creating service account with IAM role for use with FSx for Lustre CSI driver...(fsx-csi-controller-sa)${NC}"
    eksctl create iamserviceaccount \
      --name fsx-csi-controller-sa \
      --namespace kube-system \
      --cluster $EKS_CLUSTER_NAME \
      --attach-policy-arn arn:aws:iam::aws:policy/AmazonFSxFullAccess \
      --approve \
      --role-name FSXLCSI-${EKS_CLUSTER_NAME}-${AWS_REGION} \
      --region $AWS_REGION
    
    # Verify service account annotation
    echo -e "${YELLOW}Verifying service account annotation...${NC}"
    kubectl get sa fsx-csi-controller-sa -n kube-system -oyaml #retirves information about the fsx-csi-controller-sa service account 
    
    echo -e "${YELLOW} Adding the FSx for Lustre CSI Driver to helm repos...${NC}"
    # Check if repo already exists before adding it
    if ! helm repo list | grep -q "aws-fsx-csi-driver"; then
        helm repo add aws-fsx-csi-driver https://kubernetes-sigs.github.io/aws-fsx-csi-driver
    else
        echo -e "${YELLOW}Helm repository aws-fsx-csi-driver already exists, skipping add...${NC}"
    fi
    
    echo "Isntalling the FSx for Lustre CSI driver:"
    helm repo update.    
    helm upgrade --install aws-fsx-csi-driver \
      --namespace kube-system \
      --set controller.serviceAccount.create=false \
      aws-fsx-csi-driver/aws-fsx-csi-driver
    
    # Verify installation of the FSx for Lustre CSI driver
    echo -e "${YELLOW}Verifying FSx for Lustre CSI driver installation...${NC}"
    kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-fsx-csi-driver

    # Install the FSx for Lustre Storage Class using Helm
    echo -e "${YELLOW}Installing FSx for Lustre Storage Class...${NC}"
    cat > /tmp/lustre-storageclass.yaml << EOL
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: fsx-sc
provisioner: fsx.csi.aws.com
parameters:
  subnetId: \${PRIVATE_SUBNET_ID}
  securityGroupIds: \${SECURITY_GROUP_ID}
  deploymentType: PERSISTENT_2
  automaticBackupRetentionDays: "0"
  copyTagsToBackups: "true"
  perUnitStorageThroughput: "250"
  dataCompressionType: "LZ4"
  fileSystemTypeVersion: "2.15"
mountOptions:
  - flock
EOL
    
    # Create an FSx for Lustre storage class
    echo -e "Creating FSx for Lustre storage class..."
    envsubst < /tmp/lustre-storageclass.yaml | kubectl apply -f -
    
    # Verify the storage class was created
    echo -e "${YELLOW}Verifying storage class creation...${NC}"
    kubectl get sc fsx-sc -oyaml
    
    # Clean up the temporary YAML file
    rm -f /tmp/lustre-storageclass.yaml
    
    echo -e "${GREEN}✅ FSx for Lustre Storage Class setup completed${NC}"
    echo "EOL"
}


install_aws_load_balancer_controller()
{
    echo -e "${BLUE}=== Installing AWS Load Balancer Controller ===${NC}"
    
    # Create the IAM policy
    echo -e "${YELLOW}Creating IAM policy for AWS Load Balancer Controller...${NC}"
    curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/release-2.13/docs/install/iam_policy.json
    
    # Check if policy already exists
    if ! aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy-v2.12.0 \
        --policy-document file://iam_policy.json 2>/dev/null; then
        echo -e "${YELLOW}Policy AWSLoadBalancerControllerIAMPolicy-v2.12.0 already exists, continuing...${NC}"
    fi
    
    # Create a service account with IAM role
    echo -e "${YELLOW}Creating service account with IAM role...${NC}"
    eksctl create iamserviceaccount \
        --cluster=$EKS_CLUSTER_NAME \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy-v2.12.0 \
        --override-existing-serviceaccounts \
        --region $AWS_REGION \
        --approve
    
    # Verify service account annotation
    echo -e "${YELLOW}Verifying service account annotation...${NC}"
    kubectl get sa aws-load-balancer-controller -n kube-system -oyaml
    
    # Install AWS Load Balancer Controller using Helm
    echo -e "${YELLOW}Installing AWS Load Balancer Controller using Helm...${NC}"
    
    # Check if repo already exists before adding it
    if ! helm repo list | grep -q "eks"; then
        helm repo add eks https://aws.github.io/eks-charts
    else
        echo -e "${YELLOW}Helm repository eks already exists, skipping add...${NC}"
    fi
    
    helm repo update
    
    # Check if the release already exists
    if helm list -n kube-system | grep -q "aws-load-balancer-controller"; then
        echo -e "${YELLOW}AWS Load Balancer Controller already exists, upgrading...${NC}"
        helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
          -n kube-system \
          --set clusterName=$EKS_CLUSTER_NAME \
          --set serviceAccount.create=false \
          --set serviceAccount.name=aws-load-balancer-controller \
          --set region=$AWS_REGION \
          --set vpcId=$VPC_ID
    else
        echo -e "${YELLOW}Installing AWS Load Balancer Controller...${NC}"
        helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
          -n kube-system \
          --set clusterName=$EKS_CLUSTER_NAME \
          --set serviceAccount.create=false \
          --set serviceAccount.name=aws-load-balancer-controller \
          --set region=$AWS_REGION \
          --set vpcId=$VPC_ID
    fi
    
    # Verify installation
    echo -e "${YELLOW}Verifying AWS Load Balancer Controller installation...${NC}"
    kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
    
    # Clean up the policy file
    rm -f iam_policy.json
    
    echo -e "${GREEN}✅ AWS Load Balancer Controller installation completed${NC}"
    echo "EOL"
}

install_slinky_prerequisites() {
    echo -e "${BLUE}=== Installing Slinky Prerequisites ===${NC}"
    
    # Add Helm repositories
    echo -e "${YELLOW}Adding Helm repositories...${NC}"
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add jetstack https://charts.jetstack.io
    
    helm repo update
    
    # Install cert-manager
    echo -e "${YELLOW}Installing cert-manager...${NC}"
    if ! helm list -n cert-manager | grep -q "cert-manager"; then
        helm install cert-manager jetstack/cert-manager \
            --namespace cert-manager --create-namespace --set crds.enabled=true
    else
        echo -e "${YELLOW}cert-manager already exists, skipping installation...${NC}"
    fi
    
    # Install Prometheus
    echo -e "${YELLOW}Installing Prometheus...${NC}"
    if ! helm list -n prometheus | grep -q "prometheus"; then
        helm install prometheus prometheus-community/kube-prometheus-stack \
            --namespace prometheus --create-namespace --set installCRDs=true
    else
        echo -e "${YELLOW}Prometheus already exists, skipping installation...${NC}"
    fi
    
    # Verify installations
    echo -e "${YELLOW}Verifying prerequisite installations...${NC}"
    kubectl get all -n cert-manager
    kubectl get all -n prometheus
    
    # Install Slurm Operator
    echo -e "${BLUE}=== Installing Slurm Operator ===${NC}"
    
    # Download values file
    echo -e "${YELLOW}Downloading Slurm Operator values file...${NC}"
    curl -L https://raw.githubusercontent.com/SlinkyProject/slurm-operator/refs/tags/v0.3.0/helm/slurm-operator/values.yaml \
        -o values-operator.yaml
    
    # Delete any stale CRDs
    echo -e "${YELLOW}Cleaning up any stale CRDs...${NC}"
    kubectl delete crd clusters.slinky.slurm.net 2>/dev/null || true
    kubectl delete crd nodesets.slinky.slurm.net 2>/dev/null || true
    
    # Install Slurm Operator
    echo -e "${YELLOW}Installing Slurm Operator...${NC}"
    if ! helm list -n slinky | grep -q "slurm-operator"; then
        helm install slurm-operator oci://ghcr.io/slinkyproject/charts/slurm-operator \
            --values=values-operator.yaml --version=0.3.0 --namespace=slinky --create-namespace
    else
        echo -e "${YELLOW}Slurm Operator already exists, skipping installation...${NC}"
    fi
    
    # Verify Slurm Operator installation
    echo -e "${YELLOW}Verifying Slurm Operator installation...${NC}"
    kubectl get all -n slinky
    
    # Clean up values file
    rm -f values-operator.yaml
    
    echo -e "${GREEN}✅ Slinky prerequisites installation completed${NC}"
}

# Function to display the prerequisites before starting this workshop
display_important_prereqs() {
    echo -e "${BLUE}Before running this script, please ensure the following:${NC}\n"

    echo -e "${GREEN}1. 🔑 IAM Credentials:${NC}"
    echo "   You have Administrator Access Credentials in IAM."
    echo "   This is crucial as we'll be using CloudFormation to create IAM roles and policies."
    echo "   Run 'aws configure' to set up your credentials."
    echo -e "\n${GREEN}2. Build a Slurmd Deep Learning Container:${NC}"
    echo "   Build a Slurm DLC using this dockerfile: https://github.com/aws-samples/awsome-distributed-training/blob/feature/slinkly-slurm-hyperpod-eks/1.architectures/7.sagemaker-hyperpod-eks/slinky-slurm/dlc-slurmd.Dockerfile "
    echo "   following this direction: https://github.com/aws-samples/awsome-distributed-training/blob/feature/slinkly-slurm-hyperpod-eks/1.architectures/7.sagemaker-hyperpod-eks/slinky-slurm/Docker-Build-README.md"

    echo -e "\n${GREEN}3. 🔧 Packages required for this script to run:${NC}"
    echo "   Ensure you install the following: pip, jq, boto3, and jsonschema"
    echo -e "\n${YELLOW}Ready to proceed? Press Enter to continue or Ctrl+C to exit...${NC}"
    read
}

region_check() {

    NEW_REGION=$(get_input "Please, enter the AWS region where you want to set up your cluster" "us-west-2") #eks cluster name

    # echo -e "${BLUE}Please confirm that your AWS region is ${GREEN}$AWS_REGION${BLUE} (default).${NC}"

    # read -p "> " NEW_REGION

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

# Function to create cluster
install_slurm_cluster() {
    echo -e "${BLUE}=== Installing Slurm Cluster ===${NC}"
    
    # Use the environment variables
    echo -e "${YELLOW}Using environment variables:${NC}"
    echo -e "Accelerated instance type: ${GREEN}$ACCEL_INSTANCE_TYPE${NC}"
    echo -e "Accelerated instance count: ${GREEN}$ACCEL_INSTANCE_COUNT${NC}"
    echo -e "General purpose instance type: ${GREEN}$GEN_INSTANCE_TYPE${NC}"
    
    # Download base values file (using g5 as a template)
    echo -e "${YELLOW}Downloading base values file...${NC}"
    VALUES_FILE="custom-values.yaml"
    curl -L https://github.com/aws-samples/awsome-distributed-training/raw/refs/heads/feature/slinkly-slurm-hyperpod-eks/1.architectures/7.sagemaker-hyperpod-eks/slinky-slurm/g5/g5-values.yaml -o $VALUES_FILE
    if [[ $? -ne 0 ]]; then
        echo -e "${BLUE}Failed to download base values file.${NC}"
        exit 1
    fi
    
    # Verify general purpose nodes
    echo -e "${YELLOW}Verifying general purpose nodes with instance type: $GEN_INSTANCE_TYPE${NC}"
    kubectl get nodes -l node.kubernetes.io/instance-type=$GEN_INSTANCE_TYPE
    
    # Verify compute nodes
    echo -e "${YELLOW}Verifying compute nodes with instance type: $ACCEL_INSTANCE_TYPE${NC}"
    kubectl get nodes -l node.kubernetes.io/instance-type=$ACCEL_INSTANCE_TYPE
    
    # Set container image using AWS account ID
    CONTAINER_IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/dlc-slurmd:25.05.0-ubuntu24.04"
    echo -e "${YELLOW}Using container image: ${GREEN}$CONTAINER_IMAGE${NC}"
    
    # Generate SSH key if needed
    echo -e "${YELLOW}Checking for SSH key...${NC}"
    if [[ ! -f ~/.ssh/id_rsa.pub ]]; then
        echo -e "${YELLOW}No SSH key found. Generating new SSH key...${NC}"
        ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
    fi
    
    # Get SSH public key
    SSH_PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)
    
    # Update values file with user's configuration
    echo -e "${YELLOW}Customizing values file with your configuration...${NC}"
    
    # Update common affinity for non-compute components to use general purpose instance type
    sed -i '/commonAffinity:/,/values:/s/"ml.m5.2xlarge"/"'$GEN_INSTANCE_TYPE'"/g' $VALUES_FILE
    
    # Update compute node configuration
    echo -e "${YELLOW}Updating compute node configuration...${NC}"
    
    # Update container image - repository
    sed -i '/nodesets:/,/repository:/{
      /repository: "<your-account-id-here>.dkr.ecr.<your-region-here>.amazonaws.com\/dlc-slurmd"/{
        s|repository: "<your-account-id-here>.dkr.ecr.<your-region-here>.amazonaws.com/dlc-slurmd"|repository: "'"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/dlc-slurmd"'"|g
      }
    }' $VALUES_FILE
    
    # Update SSH public key
    sed -i '/rootSshAuthorizedKeys:/,/- "/{
      /- "<your-public-ssh-key-here>"/{
        s|- "<your-public-ssh-key-here>"|- "'"$SSH_PUBLIC_KEY"'"|g
      }
    }' $VALUES_FILE
            
    # Update node count to match the accelerated instance count
    sed -i '/nodesets:/,/replicas:/{
      /replicas: [0-9]\+/{
        s|replicas: [0-9]\+|replicas: '"$ACCEL_INSTANCE_COUNT"'|g
      }
    }' $VALUES_FILE
    
    # Update node selector to match the accelerated instance type (only for g5.8xlarge)
    sed -i '/nodesets:/,/nodeSelector:/{
      /node.kubernetes.io\/instance-type: ml.g5.8xlarge/{
        s|node.kubernetes.io/instance-type: ml.g5.8xlarge|node.kubernetes.io/instance-type: '"$ACCEL_INSTANCE_TYPE"'|g
      }
    }' $VALUES_FILE
    
    # Install Slurm cluster
    echo -e "${YELLOW}Installing Slurm cluster...${NC}"
    if helm list -n slinky | grep -q "slurm-cluster"; then
        echo -e "${YELLOW}Slurm cluster already exists, upgrading...${NC}"
        helm upgrade slurm-cluster oci://ghcr.io/slinkyproject/charts/slurm-cluster \
            --values=$VALUES_FILE --version=0.3.0 --namespace=slinky
    else
        echo -e "${YELLOW}Installing new Slurm cluster...${NC}"
        helm install slurm-cluster oci://ghcr.io/slinkyproject/charts/slurm-cluster \
            --values=$VALUES_FILE --version=0.3.0 --namespace=slinky
    fi
    
    # Verify installation
    echo -e "${YELLOW}Verifying Slurm cluster installation...${NC}"
    kubectl get all -n slinky
    
    # Save values file for reference
    echo -e "${YELLOW}Saving values file as ${VALUES_FILE}.used for reference${NC}"
    cp $VALUES_FILE ${VALUES_FILE}.used
    
    # Configure Login NLB
    echo -e "${YELLOW}Configuring Login Network Load Balancer...${NC}"
    # Get public subnets
    export PUBLIC_SUBNET_ID_1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=map-public-ip-on-launch,Values=true" --query "Subnets[0].SubnetId" --output text)
    export PUBLIC_SUBNET_ID_2=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=map-public-ip-on-launch,Values=true" --query "Subnets[1].SubnetId" --output text)
    
    echo -e "${YELLOW}Found public subnets: $PUBLIC_SUBNET_ID_1, $PUBLIC_SUBNET_ID_2${NC}"
    
    # Configure NLB for slurm-login service
    kubectl annotate service slurm-login -n slurm \
      service.beta.kubernetes.io/aws-load-balancer-type="nlb" \
      service.beta.kubernetes.io/aws-load-balancer-scheme="internet-facing" \
      service.beta.kubernetes.io/aws-load-balancer-nlb-target-type="ip" \
      service.beta.kubernetes.io/aws-load-balancer-subnets="$PUBLIC_SUBNET_ID_1,$PUBLIC_SUBNET_ID_2" \
      service.beta.kubernetes.io/aws-load-balancer-healthcheck-port="22" \
      --overwrite
      
    kubectl describe service slurm-login -n slurm
    
    echo -e "${GREEN}✅ Slurm cluster installation completed${NC}"
    echo -e "${GREEN}✅ You can access the Slurm cluster using:${NC}"
    echo -e "${YELLOW}kubectl exec -it -n slinky deployment/slurm-cluster-login -- /bin/bash${NC}"
    echo -e "${YELLOW}Note: It may take a few minutes for all components to start up${NC}"
}

# Function to deploy Slurm cluster
deploy_slurm_cluster() {
    local namespace="${1:-slurm}"
    local values_file="${2:-custom-values.yaml}"
    local version="${3:-0.3.0}"
    local dry_run="${4:-false}"
    local configure_nlb="${5:-false}"
    
    echo -e "${BLUE}=== Deploying Slurm Cluster ===${NC}"
    
    # Verify the values file exists
    if [[ ! -f "$values_file" ]]; then
        echo -e "${RED}Error: Values file $values_file not found${NC}"
        return 1
    fi
    
    # Perform dry run if requested
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}Performing dry run installation...${NC}"
        helm install --dry-run slurm oci://ghcr.io/slinkyproject/charts/slurm \
            --values="$values_file" --version="$version" --namespace="$namespace"
        
        # Check if dry run was successful
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Dry run failed. Please check the values file and try again.${NC}"
            return 1
        fi
        echo -e "${GREEN}Dry run completed successfully.${NC}"
        
        # Don't proceed further if this is just a dry run
        if [[ "$dry_run" == "true" ]]; then
            return 0
        fi
    fi
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        echo -e "${YELLOW}Creating namespace $namespace...${NC}"
        kubectl create namespace "$namespace"
    fi
    
    # Perform actual installation
    echo -e "${YELLOW}Installing Slurm cluster...${NC}"
    helm install slurm oci://ghcr.io/slinkyproject/charts/slurm \
        --values="$values_file" --version="$version" --namespace="$namespace"
    
    # Check if installation was successful
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Installation failed. Please check the error messages above.${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Slurm cluster installation initiated${NC}"
    
    # Watch the deployment status
    echo -e "${YELLOW}Watching deployment status...${NC}"
    kubectl -n "$namespace" get pods -l app.kubernetes.io/instance=slurm --watch &
    watch_pid=$!
    
    # Allow user to stop watching after a while
    sleep 10
    echo -e "\n${YELLOW}Press Enter to stop watching and continue...${NC}"
    read -t 60  # Wait for user input or timeout after 60 seconds
    kill $watch_pid 2>/dev/null
    
    # Verify the deployment status of all components
    echo -e "${YELLOW}Verifying deployment status of all components...${NC}"
    kubectl get all -n "$namespace"
    
    echo -e "${GREEN}✅ Slurm cluster deployment completed${NC}"
    echo -e "${YELLOW}Note: It may take a few minutes for all components to start up${NC}"
    
    # Configure NLB if requested
    if [[ "$configure_nlb" == "true" ]]; then
        echo -e "${YELLOW}Configuring Network Load Balancer for login access...${NC}"
        # Wait a bit for the service to be created
        sleep 10
        configure_login_nlb "$namespace" "slurm-login"
    fi
    
    return 0
}

# Function to configure a Login Network Load Balancer
configure_login_nlb() {
    local namespace="${1:-slurm}"
    local service_name="${2:-slurm-login}"
    
    echo -e "${BLUE}=== Configuring Login Network Load Balancer ===${NC}"
    
    # Identify public subnets in the VPC
    echo -e "${YELLOW}Identifying public subnets in VPC...${NC}"
    export PUBLIC_SUBNET_ID_1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=map-public-ip-on-launch,Values=true" --query "Subnets[0].SubnetId" --output text)
    export PUBLIC_SUBNET_ID_2=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=map-public-ip-on-launch,Values=true" --query "Subnets[1].SubnetId" --output text)
    
    # Verify subnets were found
    if [[ -z "$PUBLIC_SUBNET_ID_1" || "$PUBLIC_SUBNET_ID_1" == "None" || -z "$PUBLIC_SUBNET_ID_2" || "$PUBLIC_SUBNET_ID_2" == "None" ]]; then
        echo -e "${RED}Error: Could not find two public subnets in VPC ${VPC_ID}${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Found public subnets: ${PUBLIC_SUBNET_ID_1}, ${PUBLIC_SUBNET_ID_2}${NC}"
    
    # Add annotations to the service to make it internet facing
    echo -e "${YELLOW}Adding annotations to ${service_name} service...${NC}"
    kubectl annotate service ${service_name} -n ${namespace} \
      service.beta.kubernetes.io/aws-load-balancer-type="nlb" \
      service.beta.kubernetes.io/aws-load-balancer-scheme="internet-facing" \
      service.beta.kubernetes.io/aws-load-balancer-nlb-target-type="ip" \
      service.beta.kubernetes.io/aws-load-balancer-subnets="${PUBLIC_SUBNET_ID_1},${PUBLIC_SUBNET_ID_2}" \
      service.beta.kubernetes.io/aws-load-balancer-healthcheck-port="22" \
      --overwrite
    
    # Verify the service configuration
    echo -e "${YELLOW}Verifying service configuration...${NC}"
    kubectl describe service ${service_name} -n ${namespace}
    
    # Get the NLB DNS name
    NLB_DNS=$(kubectl get service ${service_name} -n ${namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    if [[ -n "$NLB_DNS" ]]; then
        echo -e "${GREEN}✅ Login NLB configured successfully${NC}"
        echo -e "${GREEN}✅ You can access the Slurm login node using:${NC}"
        echo -e "${YELLOW}ssh -i ~/.ssh/id_rsa <username>@${NLB_DNS}${NC}"
    else
        echo -e "${YELLOW}NLB DNS name not yet available. It may take a few minutes to provision.${NC}"
        echo -e "${YELLOW}Run the following command later to get the DNS name:${NC}"
        echo -e "${YELLOW}kubectl get service ${service_name} -n ${namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'${NC}"
    fi
    
    return 0
}

create_and_verify_fsx_pvc() {
    local namespace="slurm"
    local pvc_name="fsx-claim"
    local max_retries=30
    local retry_interval=10

    echo "Creating FSx for Lustre PVC in ${namespace} namespace..."

    # Create namespace if it doesn't exist
    if ! kubectl get namespace ${namespace} >/dev/null 2>&1; then
        echo "Creating namespace: ${namespace}"
        kubectl create ns ${namespace}
        if [ $? -ne 0 ]; then
            echo "Failed to create namespace ${namespace}"
            return 1
        fi
    fi

    local yaml_file="lustre-pvc-slurm.yaml"
    local yaml_url="https://github.com/aws-samples/awsome-distributed-training/raw/refs/heads/feature/slinkly-slurm-hyperpod-eks/1.architectures/7.sagemaker-hyperpod-eks/slinky-slurm/lustre-pvc-slurm.yaml"

    if [ ! -f "${yaml_file}" ]; then
        echo "PVC YAML file not found. Downloading from repository..."
        if ! curl -s -L -o "${yaml_file}" "${yaml_url}"; then
            echo "Failed to download ${yaml_file}"
            return 1
        fi
        echo "Successfully downloaded ${yaml_file}"
    else
        echo "Using existing ${yaml_file}"
    fi

    # Apply the PVC configuration
    echo "Creating PVC ${pvc_name}..."
    kubectl apply -f "${yaml_file}"
    if [ $? -ne 0 ]; then
        echo "Failed to apply PVC configuration"
        return 1
    fi

    # Wait for PVC to be bound
    echo "Waiting for PVC to be bound..."
    for ((i=1; i<=max_retries; i++)); do
        status=$(kubectl get pvc ${pvc_name} -n ${namespace} -ojson | jq -r .status.phase)
        if [ "$status" == "Bound" ]; then
            echo "PVC successfully bound!"
            break
        fi
        if [ $i -eq $max_retries ]; then
            echo "Timeout waiting for PVC to be bound. Current status: ${status}"
            return 1
        fi
        echo "Current status: ${status}, waiting ${retry_interval} seconds... (Attempt ${i}/${max_retries})"
        sleep ${retry_interval}
    done

    # Get and display PVC details
    echo "PVC Details:"
    kubectl get pvc -n ${namespace}

    # Get volume ID
    volume_name=$(kubectl get pvc ${pvc_name} -n ${namespace} -ojson | jq -r .spec.volumeName)
    if [ -n "$volume_name" ]; then
        volume_id=$(kubectl get pv ${volume_name} -ojson | jq -r .spec.csi.volumeHandle)
        echo "Volume ID: ${volume_id}"
    else
        echo "Failed to get volume name"
        return 1
    fi

    return 0
}

# Warning message function
warning() {
    echo -e "${BLUE}⚠️  Please note:${NC}"
    echo -e "   - Cluster creation may take some time (~15-20 min)"
    echo -e "   - This operation may incur costs on your AWS account"
    echo -e "   - Ensure you understand the implications before proceeding\n"
}

# Function to check and fix Kubernetes connectivity
check_kubernetes_connectivity() {
    echo -e "${BLUE}=== Checking Kubernetes Connectivity ===${NC}"
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}kubectl not found. Please install kubectl first.${NC}"
        return 1
    fi
    
    # Check current context
    echo -e "${YELLOW}Current kubectl context:${NC}"
    kubectl config current-context || {
        echo -e "${RED}No current context set.${NC}"
        return 1
    }
    
    # Try to get cluster info
    echo -e "${YELLOW}Testing connection to Kubernetes cluster...${NC}"
    if ! kubectl cluster-info; then
        echo -e "${RED}Cannot connect to Kubernetes cluster.${NC}"
        
        # Check AWS CLI configuration
        echo -e "${YELLOW}Checking AWS CLI configuration...${NC}"
        aws sts get-caller-identity || {
            echo -e "${RED}AWS CLI not properly configured. Please run 'aws configure'.${NC}"
            return 1
        }
        
        # Check if EKS cluster exists
        echo -e "${YELLOW}Checking EKS clusters in region ${AWS_REGION}...${NC}"
        CLUSTERS=$(aws eks list-clusters --region ${AWS_REGION} --query 'clusters' --output text)
        
        if [[ -z "$CLUSTERS" ]]; then
            echo -e "${RED}No EKS clusters found in region ${AWS_REGION}.${NC}"
            return 1
        fi
        
        echo -e "${GREEN}Available clusters: ${CLUSTERS}${NC}"
        echo -e "${YELLOW}Please select a cluster to connect to:${NC}"
        read -p "Cluster name: " CLUSTER_NAME
        
        # Update kubeconfig for the selected cluster
        echo -e "${YELLOW}Updating kubeconfig for cluster ${CLUSTER_NAME}...${NC}"
        aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION} || {
            echo -e "${RED}Failed to update kubeconfig.${NC}"
            return 1
        }
        
        # Test connection again
        echo -e "${YELLOW}Testing connection again...${NC}"
        if ! kubectl cluster-info; then
            echo -e "${RED}Still cannot connect to Kubernetes cluster.${NC}"
            echo -e "${YELLOW}Checking DNS resolution...${NC}"
            
            # Extract API server hostname from kubeconfig
            API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | sed 's|https://||')
            echo -e "${YELLOW}API Server: ${API_SERVER}${NC}"
            
            # Check DNS resolution
            if ! nslookup ${API_SERVER}; then
                echo -e "${RED}DNS resolution failed for ${API_SERVER}.${NC}"
                echo -e "${YELLOW}Checking DNS settings...${NC}"
                
                # Check resolv.conf
                cat /etc/resolv.conf
                
                echo -e "${YELLOW}You may need to update your DNS settings or add an entry to /etc/hosts.${NC}"
                echo -e "${YELLOW}Would you like to try using the AWS VPC DNS server? (y/n)${NC}"
                read -p "" USE_VPC_DNS
                
                if [[ "$USE_VPC_DNS" == "y" ]]; then
                    # Get VPC ID from cluster
                    VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.vpcId' --output text)
                    
                    # Get VPC DNS server (VPC DNS is always at the +2 address of the VPC CIDR)
                    VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids ${VPC_ID} --region ${AWS_REGION} --query 'Vpcs[0].CidrBlock' --output text)
                    VPC_DNS=$(echo ${VPC_CIDR} | awk -F'.' '{print $1"."$2".0.2"}') 
                    
                    echo -e "${YELLOW}VPC DNS server: ${VPC_DNS}${NC}"
                    echo -e "${YELLOW}Adding temporary DNS server to resolv.conf...${NC}"
                    echo -e "${RED}Note: This requires sudo access and is temporary${NC}"
                    echo "nameserver ${VPC_DNS}" | sudo tee -a /etc/resolv.conf
                    
                    # Test connection again
                    echo -e "${YELLOW}Testing connection again...${NC}"
                    kubectl cluster-info
                fi
            fi
            
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ Successfully connected to Kubernetes cluster${NC}"
    return 0
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
    print_header "🚀 Welcome to the SageMaker HyperPod Slurm Cluster Creation Script! 🚀"

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
    
    # Check Kubernetes connectivity before proceeding
    echo -e "\n${BLUE}🔌 Checking Kubernetes Connectivity${NC}"
    check_kubernetes_connectivity || {
        echo -e "${RED}Failed to establish Kubernetes connectivity. Please fix the issues before proceeding.${NC}"
        exit 1
    }
    
    #creating the cloudformation stack

    # Cluster Configuration
    #echo -e "\n${BLUE}🚀 Creating the Cluster${NC}"
    echo -e "${BLUE} Generating cluster configuration...${NC}"
    create_config #also calls the cloufromation stack and is created at this step 
    create_fsx_lustre_storage_class 
    install_aws_load_balancer_controller
    install_slinky_prerequisites
    # Option 1: Use the existing install_slurm_cluster function
    # install_slurm_cluster
    
    # Option 2: Use the encapsulated deploy_slurm_cluster function
    deploy_slurm_cluster "slurm" "custom-values.yaml" "0.3.0" "false" "true"
    create_and_verify_fsx_pvc
    
    echo -e "${GREEN}✅ Cluster configuration created successfully${NC}"
    echo -e "${BLUE}ℹ️  Validating the generated configuration before proceeding${NC}"
    
    # Display goodbye message
    goodbye
}

# Execute the main function
main