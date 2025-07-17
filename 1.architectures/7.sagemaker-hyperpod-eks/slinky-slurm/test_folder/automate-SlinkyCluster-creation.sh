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
    CONTROLLER_TYPE=$(get_input "Enter the instance type for the controller" "ml.m5.8xlarge")

   

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
    echo -e "\n${GREEN}3. 📊 Observability Stack:${NC}"
    echo "   It's highly recommended to deploy the observability stack as well."
    echo "   Navigate to https://catalog.workshops.aws/sagemaker-hyperpod/en-US/00-setup/02-own-account#2.-deploy-cluster-observability-stack-(recommended) to deploy the stack"
    echo -e "\n${GREEN}5. 🔧 Packages required for this script to run:${NC}"
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

# Function to create users in cluster

validate_cluster_config() {
    echo "Validating your cluster configuration..."
    # TODO: MAKE SURE PACKAGES ARE INSTALLED HERE!!

    curl -O https://raw.githubusercontent.com/aws-samples/awsome-distributed-training/main/1.architectures/5.sagemaker-hyperpod/validate-config.py

    # check config for known issues
    python3 validate-config.py --cluster-config cluster-config.json --provisioning-parameters provisioning_parameters.json --region $AWS_REGION
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
    #creating the cloudformation stack

    # Cluster Configuration
    #echo -e "\n${BLUE}🚀 Creating the Cluster${NC}"
    echo -e "${BLUE} Generating cluster configuration...${NC}"
    create_config #also calls the cloufromation stack and is created at this step 
    create_fsx_lustre_storage_class 
    install_aws_load_balancer_controller
    install_slinky_prerequisites

    echo -e "${GREEN}✅ Cluster configuration created successfully${NC}"
    echo -e "${BLUE}ℹ️  Validating the generated configuration before proceeding${NC}"


main