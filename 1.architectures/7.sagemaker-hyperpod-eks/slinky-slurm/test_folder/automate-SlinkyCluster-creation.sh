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

    # --------------------------
    # Write instance mappings
    # --------------------------
    echo "export EKS_CLUSTER_NAME=${EKS_CLUSTER_NAME}" >> env_vars
    echo "[INFO] EKS_CLUSTER_NAME = ${EKS_CLUSTER_NAME}"
    echo "export ACCEL_INSTANCE_TYPE=${INSTANCE_TYPE}" >> env_vars
    echo "export ACCEL_INSTANCE_COUNT=${INSTANCE_COUNT}" >> env_vars
    echo "export GEN_INSTANCE_TYPE=${CONTROLLER_TYPE}" >> env_vars
    echo "export GEN_INSTANCE_COUNT=${CONTROLLER_COUNT}" >> env_vars

    EKS_CLUSTER_INFO=$(aws eks describe-cluster --name "$STACK_ID" --region "$AWS_REGION") #Eks cluster information

    # --------------------------
    # Get EKS_CLUSTER_ARN from CloudFormation
    # --------------------------
    EKS_CLUSTER_ARN=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_ID" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`EKSClusterArn`].OutputValue' \
        --output text)

    if [[ -n "$EKS_CLUSTER_ARN" && "$EKS_CLUSTER_ARN" != "None" ]]; then
        echo "export EKS_CLUSTER_ARN=${EKS_CLUSTER_ARN}" >> env_vars
        echo "[INFO] EKS_CLUSTER_ARN = ${EKS_CLUSTER_ARN}"
    else
        echo "[ERROR] Failed to retrieve EKS_CLUSTER_ARN from CloudFormation."
        return 1
    fi

    # --------------------------
    # Get S3_BUCKET_NAME
    # --------------------------
    S3_BUCKET_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_ID" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
        --output text)

    if [[ -n "$S3_BUCKET_NAME" && "$S3_BUCKET_NAME" != "None" ]]; then
        echo "export S3_BUCKET_NAME=${S3_BUCKET_NAME}" >> env_vars
        echo "[INFO] S3_BUCKET_NAME = ${S3_BUCKET_NAME}"
    else
        echo "[ERROR] Failed to retrieve S3_BUCKET_NAME from CloudFormation."
        return 1
    fi

    # --------------------------
    # Get EXECUTION_ROLE
    # --------------------------

    #eks roleARN
    # export EKS_ROLE_ARN=$(echo "$EKS_CLUSTER_INFO" | jq -r '.cluster.roleArn')
    # echo "export EKS_ROLE_ARN=${EKS_ROLE_ARN}" >> env_vars
    # echo "[INFO] EKS_ROLE_ARN = ${EKS_ROLE_ARN}"


    #SageMakerIAMRoleArn
    EXECUTION_ROLE=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_ID" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`SageMakerIAMRoleArn`].OutputValue' \
        --output text)
    

    if [[ -n "$EXECUTION_ROLE" && "$EXECUTION_ROLE" != "None" ]]; then
        echo "export EXECUTION_ROLE=${EXECUTION_ROLE}" >> env_vars
        echo "[INFO] EXECUTION_ROLE = ${EXECUTION_ROLE}"
    else
        echo "[ERROR] Failed to retrieve EXECUTION_ROLE from CloudFormation."
        return 1
    fi

    # --------------------------
    # Get VPC_ID
    # --------------------------
    VPC_ID=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_ID" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
        --output text)

    if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
        echo "export VPC_ID=${VPC_ID}" >> env_vars
        echo "[INFO] VPC_ID = ${VPC_ID}"
    else
        echo "[ERROR] Failed to retrieve VPC_ID from CloudFormation."
        return 1
    fi

    #EKS Cluster subnet 

    # --------------------------
    # Get PRIVATE_SUBNET_ID directly from EKS cluster
    # --------------------------
    echo "[INFO] Retrieving subnet information from EKS cluster ${EKS_CLUSTER_NAME}..."
    
    # Get cluster VPC configuration
    # Extract the first private subnet ID
    export PRIVATE_SUBNET_ID=$(echo "$EKS_CLUSTER_INFO" | jq -r '.cluster.resourcesVpcConfig.subnetIds[0]')
    
    if [[ -n "$PRIVATE_SUBNET_ID" && "$PRIVATE_SUBNET_ID" != "null" ]]; then
        echo "export PRIVATE_SUBNET_ID=${PRIVATE_SUBNET_ID}" >> env_vars
        echo "[INFO] PRIVATE_SUBNET_ID = ${PRIVATE_SUBNET_ID}"
    else
        echo "[ERROR] Failed to retrieve PRIVATE_SUBNET_ID from EKS cluster."
        return 1
    fi

    # --------------------------
    # Get SECURITY_GROUP_ID
    # --------------------------
    SECURITY_GROUP_ID=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_ID" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`SecurityGroupId`].OutputValue' \
        --output text)

    if [[ -n "$SECURITY_GROUP_ID" && "$SECURITY_GROUP_ID" != "None" ]]; then
        echo "export SECURITY_GROUP_ID=${SECURITY_GROUP_ID}" >> env_vars
        echo "[INFO] SECURITY_GROUP_ID = ${SECURITY_GROUP_ID}"
    else
        echo "[ERROR] Failed to retrieve SECURITY_GROUP_ID from CloudFormation."
        return 1
    fi

    # --------------------------
    # Source the generated variables
    # --------------------------
    source env_vars
    
    # Update kubectl config to point to the correct cluster
    echo -e "${YELLOW}Updating kubectl configuration to use cluster: ${EKS_CLUSTER_NAME}${NC}"
    aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION

    # --------------------------
    # Summary
    # --------------------------
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
    #EXECUTION_ROLE=$([ "${MH:-false}" = true ] && echo "${SLURM_EXECUTION_ROLE_ARN}" || echo "${ROLE}")

    # Add worker instance groups
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
        \"ExecutionRole\": \"${EXECUTION_ROLE}\",
        \"ThreadsPerCore\": 2" 

    INSTANCE_GROUPS+="
    }"  

    echo -e "${GREEN}✅ Worker Group $WORKER_GROUP_COUNT added${NC}"      
    ((WORKER_GROUP_COUNT++))
    #done         
    INSTANCE_GROUPS+="]"
    #done with the instance array 

    # read -e -p "What would you like to name your cluster? (default: slinky-cluster): " CLUSTER_NAME
    # CLUSTER_NAME=${CLUSTER_NAME:-slinky-cluster}

    # Create the cluster-config.json file
    cat > cluster-config.json << EOL
    {
        "ClusterName": "$EKS_CLUSTER_NAME",
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
    echo
    echo -e "${BLUE}=== Creating FSx for Lustre Storage Class ===${NC}"
    
    # Create an IAM OpenID Connect (OIDC) identity provider for the cluster
    echo -e "${YELLOW}Creating IAM OIDC identity provider...${NC}"
    eksctl utils associate-iam-oidc-provider --cluster $EKS_CLUSTER_NAME --approve
    
    # Create a service account with an IAM role for the FSx for Lustre CSI driver
    echo -e "${YELLOW}Creating service account with IAM role for use with FSx for Lustre CSI driver...(fsx-csi-controller-sa)${NC}"
    #this creates a new stack there shoud not be an 
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
    helm repo update  
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
    echo
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
    echo -e "${YELLOW}Verifying Load balance contoller service account annotation (aws-load-balancer-controller) ${NC}"
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
    echo
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
    
    # # Install cert-manager
    # echo -e "${YELLOW}Installing cert-manager...${NC}"
    # if ! helm list -n cert-manager | grep -q "cert-manager"; then
    #     helm install cert-manager jetstack/cert-manager \
    #         --namespace cert-manager --create-namespace --set crds.enabled=true
    # else
    #     echo -e "${YELLOW}cert-manager already exists, skipping installation...${NC}"
    # fi

    echo -e "${YELLOW}Installing cert-manager...${NC}"
    if ! helm list -n cert-manager | grep -q "cert-manager"; then
        # Temporarily disable the AWS Load Balancer webhook
        echo -e "${YELLOW}Temporarily disabling AWS Load Balancer webhook...${NC}"
        kubectl delete -A ValidatingWebhookConfiguration aws-load-balancer-webhook --ignore-not-found=true
        
        # Create namespace
        kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
        
        # Apply CRDs
        kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.crds.yaml
        
        # Install cert-manager
        helm install cert-manager jetstack/cert-manager \
            --namespace cert-manager \
            --set installCRDs=false \
            --timeout 5m
        
        # Restart the AWS Load Balancer Controller
        kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
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