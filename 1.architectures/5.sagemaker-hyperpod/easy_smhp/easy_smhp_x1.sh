#!/bin/bash
# Automatizing the full Workshop available at:
# - https://catalog.workshops.aws/sagemaker-hyperpod
# - https://catalog.workshops.aws/sagemaker-hyperpod-eks
unset az, region, controller, login, worker # DO NOT TOUCH
unset subnet_private_id, fsxl_id, fsxl_mount, sg, role_name, bucket # DO NOT TOUCH

# INPUT from Customer
export orchestrator="eks" # slurm or eks
export verbose="true" # Display actions taken to run this script
export install_dir="/tmp/smhp_install" # folder to copy, create, install software and configuration files
export bin_dir="/usr/local/bin" # folder to store the binaries installed
export venv_smhp="${install_dir}/venv" # Virtual Environment for local Python installation
export VolumeSizeInGB=500 # Instances root EBS volume size
export region="us-west-2" # Virginia/us-east-1/use1-azX Ohio:us-east-2/use2-azX California/us-west-1/usw1-azX Oregon/us-west-2/usw2-azX Sidney/ap-southeast-2/apse2-azX Dublin/eu-west-1/euw1-azX
export az="usw2-az1" # set if you want to deploy a NEW VPC stack, unset if already deployed
export vpc_cf_stack_name="vpc-smhp-eks-test-1" # vpc_cf_stack_name="sagemaker-hyperpod"
export observability_cf_stack_name="Hyperpod-Cluster-Observability" # Slurm only -  unset to deactivate
export SMHP_ClusterName="ml-cluster-gui1" # ClusterName="ml-cluster"
export EKS_ResourceNamePrefix="gui-smhp-eks-test-1" # "-cluster" will be added to it to name the EKS cluster


declare -A controller=( # controller node [instance_type]=count for Slurm orchestrator only
    [ml.m5.4xlarge]="1"
)
declare -A login=( # login node [instance_type]=count for Slurm orchestrator only
    [ml.m5.4xlarge]="1"
    # [ml.m5.4xlarge]="2"
    # [ml.m5.4xlarge]="2"
)
declare -A worker=( # worker node [instance_type]=count
    # [ml.g5.8xlarge]="1"
    [ml.m5.4xlarge]="1"
)
declare -A tag=( # SMHP cluster tags [Key]=Value
    [project]="p1"
    [cost]="c1"
)


### Do not set below variables except if you want to override the CloudFormation stack output's
# AmazonS3BucketName="" # S3 bucket for Life Cycle Scripts - if set, it overrides the VPC CloudFormation stack output's
# PrimaryPrivateSubnet="" # Private Subnet ID (subnet-xxxxxx) - if set, it overrides the VPC CloudFormation stack output's
# FSxLustreFilesystemMountname="" # FSx Lustre mount name (abcde1234) - if set, it overrides the VPC CloudFormation stack output's
# cf_FSxLustreFilesystemDNSname="" # FSx Lustre DNS name (fs-xxxxxxx.fsx.${region}.amazonaws.com) - if set, it overrides the VPC CloudFormation stack output's
# AmazonSagemakerClusterExecutionRoleArn="" # IAM Execution Role ARN - if set, it overrides the VPC CloudFormation stack output's
# FSxLustreFilesystemId="" # FSx Lustre FS ID (fs-xxxxxxxx) - if set, it overrides the VPC CloudFormation stack output's
# SecurityGroup="" # Security Group (sg-xxxxxxxxx) - if set, it overrides the VPC CloudFormation stack output's

# Internal Enviromment variables - Should not be touched
export AWS_PAGER="" # deactivate AWS CLI paging

awscli_pkg="awscli-exe-linux-x86_64.zip" # AWS CLI file name
awscli_url="https://awscli.amazonaws.com/${awscli_pkg}" # AWS CLI url to download and install it
gh_adt_url="aws-samples/awsome-distributed-training" # GitHub name of the awsome-distributed-training repo
gh_adt_dir="$(basename "${gh_adt_url}")" # awsome-distributed-training repo folder name
smhp_config="cluster-config.json" # SMHP cluster config file name
env_vars="env_vars" # environement variables exported to be used in further scripts
instances_types="${!controller[@]} ${!login[@]} ${!worker[@]}" # complete list of all instance types used in the SMHP cluster to check quotas

case "${orchestrator}" in
    slurm)
        vpc_cf_stack_file="sagemaker-hyperpod.yaml"
        vpc_cf_stack_url="https://awsome-distributed-training.s3.amazonaws.com/templates/${vpc_cf_stack_file}" # should use local file
        observability_cf_stack_url="https://awsome-distributed-training.s3.amazonaws.com/templates/cluster-observability.yaml"
        ;;
    eks)
        vpc_cf_stack_file="hyperpod-eks-full-stack.yaml"
        vpc_cf_stack_url="https://ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0.s3.us-west-2.amazonaws.com/2433d39e-ccfe-4c00-9d3d-9917b729258e/${vpc_cf_stack_file}" # should use local file
        observability_cf_stack_url=""
        ;;
    *)
        pecho "ERROR: unknown orchestrator \"${orchestrator}\""
        exit 1
        ;;
esac

# Slurm only
lcs_path="${gh_adt_dir}/1.architectures/5.sagemaker-hyperpod/LifecycleScripts/base-config"
smhp_provisioning="provisioning_parameters.json"
account_id="$(aws sts get-caller-identity | jq -r '.Account')"

# EKS only
NodeRecovery="Automatic" # EKS only (string) default to "Automatic" - Enable node auto-recovery. Set to "None" to disable.
kubectl_url="https://s3.${region}.amazonaws.com/amazon-eks/1.29.3/2024-04-19/bin/linux/amd64/kubectl"
eksctl_url="https://github.com/eksctl-io/eksctl/releases/latest/download"
helm_url="https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"
smhp_eks_policy_name="hyperpod-eks-policy"
lcs_eks_path="https://raw.githubusercontent.com/aws-samples/awsome-distributed-training/main/1.architectures/7.sagemaker-hyperpod-eks/LifecycleScripts/base-config/on_create.sh"
gh_smhpcli_dir="sagemaker-hyperpod-cli" # aws/sagemaker-hyperpod-cli.git
gh_smhpcli_url="aws/${gh_smhpcli_dir}"
aws_fsx_csi_url="https://kubernetes-sigs.github.io/aws-fsx-csi-driver"
role_user_name=$(aws sts get-caller-identity --query "Arn" --output text | cut -d':' -f6 |cut -d'/' -f2 )
role_user_arn=$(aws sts get-caller-identity --query "Arn" --output text )
# nsight_sidecar="https://helm.ngc.nvidia.com/nvidia/devtools/charts/devtools-sidecar-injector-1.0.7.tgz"

# pretty echo
pecho(){
    echo
    echo "############## $@"
}

# execute a command, print it first if verbose is set, exit if return code is non valid
run(){
    cmd="$@"
    if [[ "$verbose" == "true" ]] ;then
        echo "##### Running: \"${cmd}\" >"
    fi
    eval "${cmd}"
    ret="$?"
    if [[ ${ret} -ne 0 ]] ;then
        echo
        echo "##### Failed #####"
        exit ${ret}
    fi
}

# same as run() but dedicated for validate-config.py only
# workaround for validate-config.py which does not return a valid error when failing
run_spe(){
    cmd="$@"
    if [[ "$verbose" == "true" ]] ;then
        echo "##### Running: \"${cmd}\" >"
    fi
    output=$(eval "${cmd}")
    echo "${output}"
    echo "${output}" | grep invalid &>/dev/null
    if [[ ${?} -eq 0 ]] ;then
        echo
        echo "##### Failed #####"
        exit 1
    fi
}

# check all commands in args exist in path
dep_check(){
    for c in ${@} ;do
        # $c --version | head -n1
        if ! command -v $c &> /dev/null ; then
            echo "[WARNING] Command \"${c}\" can not be found." >&2
            # exit -1
        fi
    done
}

# wait for the CF stack in arg to be complete
cf_wait(){
    local stack="${1}"

    if [[ -n ${stack} ]] ;then
        pecho "Waiting on CloudFormation stack \"${stack}\" to be fully deployed..."
        aws cloudformation wait stack-create-complete --stack-name "${stack}"
        if [[ $? -eq 0 ]] ;then
            echo "...CloudFormation stack \"${stack}\" is deployed."
        else
            echo "ERROR: failed to wait on CloudFormation stack \"${stack}\""
            exit 1
        fi
    fi
}

# get a specific var out of a CF stack
cf_get_var(){
    cf_stack_name="${1}"
    var="${2}"
    output=$(aws cloudformation describe-stacks \
            --stack-name "${cf_stack_name}" \
            --query "Stacks[0].Outputs[?OutputKey==\`${var}\`].OutputValue" \
        --output text)
    # --region "${region}"

    echo "${output}"
}

# unset all variables from the CF stack from the environment
cf_unset_vars_all(){
    cf_stack_name="${1}"
    output=$(aws cloudformation describe-stacks --stack-name "${cf_stack_name}" --output json 2>/dev/null)
    if [[ $? -eq 0 ]] ;then
        echo -n "Unsetting: "
        for var in $(echo "${output}" | jq -r ".Stacks[].Outputs[].OutputKey") ;do
            unset "${var}"
            echo -n "${var} "
        done | xargs echo -n | sed 's/ /, /g'
        echo '.'
    fi
}

# export all variables from the CF stack to the environment
cf_export_all(){
    cf_stack_name="${1}"
    output=$(aws cloudformation describe-stacks --stack-name "${cf_stack_name}" --output json | jq ".Stacks[].Outputs")
    # --region "${region}"
    read -d '' -r -a key <<< $(echo "${output}" | jq -r ".[].OutputKey")
    read -d '' -r -a val <<< $(echo "${output}" | jq -r ".[].OutputValue")
    for ((i=0;i<${#key[@]};++i)); do
        # export "cf_${key[i]}"="${val[i]}"
        # echo export "cf_${key[i]}"="${val[i]}"
        if [[ -z "${!key[i]}" ]] ;then
            # from cf stack
            export "${key[i]}"="${val[i]}"
            echo export "${key[i]}"="${val[i]}" | tee -a ${env_vars}
        else
            # Recap Customer input, already exported
            echo export "${key[i]}"="${!key[i]}" | tee -a ${env_vars}
        fi
    done
}

# pre-initialize the environement
init_env_pre(){
    pecho "Pre-initialize the environement"
    
    dep_check jq aws curl wget sed tr awk column
    pwd_previous="$(pwd)"
    pecho "Moving to ${install_dir}"
    mkdir -p "${install_dir}"
    mkdir -p "${bin_dir}"
    cd "${install_dir}"
    rm -f "${env_vars}"

    region_previous=$(aws configure get region)
    pecho "Current aws-cli region is set to \"${region_previous}\", setting it to \"${region}\""
    export AWS_REGION="$region"
    run aws configure set region $region # to avoid difference between configuration
}

# checking ${SMHP_ClusterName} as SMHP cluster name, failing if already existing
smhp_check_cluster(){
    pecho "Checking if the HyperPod cluster \"${SMHP_ClusterName}\" exists already:"

    aws sagemaker describe-cluster --cluster-name "${SMHP_ClusterName}" &> /dev/null
    if [[ $? -eq 0 ]] ;then
        status=$(aws sagemaker describe-cluster --cluster-name "${SMHP_ClusterName}" | jq -r .ClusterStatus)
        pecho "Stopping: the HyperPod cluster \"${SMHP_ClusterName}\" exists already with the status \"${status}\"."
        echo "You can change the ClusterName variable or delete it with:"
        echo "aws sagemaker delete-cluster --cluster-name \"${SMHP_ClusterName}\""
        echo
        exit 1
    else
        echo "using \"${SMHP_ClusterName}\" as cluster name."
    fi
}

# listing SMHP cluters
smhp_list(){
    pecho "Listing current sagemaker HyperPod clusters:"
    run 'aws sagemaker list-clusters --output text | sed "s/CLUSTERSUMMARIES//g" | column -t'
}


# Downloading and Deploying the VPC stack ${vpc_cf_stack_name} using environment variables
# waiting on its deployement and exporting the output variables
vpc_stack_deploy(){
    pecho "Downloading and Deploying the VPC stack \"${vpc_cf_stack_name}\""
    run wget -q "${vpc_cf_stack_url}" # should use local file instead
        
    case "${orchestrator}" in
                slurm)
                    run aws cloudformation deploy \
                        --capabilities CAPABILITY_NAMED_IAM \
                        --stack-name "${vpc_cf_stack_name}" \
                        --template-file  "${vpc_cf_stack_file}" \
                        --parameter-overrides \
                        VPCName="SageMaker HyperPod VPC"\
                        PrimarySubnetAZ=${az}\
                        BackupSubnetAZ=""\
                        CreateS3Endpoint='true'\
                        Capacity=1200\
                        S3Bucket="sagemaker-lifecycle"\
                        PerUnitStorageThroughput=250\
                        Compression="LZ4"
                ;;
                eks)
                    run aws cloudformation deploy \
                        --capabilities CAPABILITY_NAMED_IAM \
                        --stack-name "${vpc_cf_stack_name}" \
                        --template-file  "${vpc_cf_stack_file}" \
                        --parameter-overrides \
                        AvailabilityZoneId="${az}" \
                        ResourceNamePrefix="${EKS_ResourceNamePrefix}"
                ;;
    esac    

    cf_wait "${vpc_cf_stack_name}"
    cf_export_all "${vpc_cf_stack_name}"
}

# checking the VPC stack has been deployed with the expected AZ
# deploying it if needed
vpc_stack_check_deploy(){
    if [[ ${vpc_cf_stack_name} ]] ;then
        pecho "Checking about the VPC stack \"${vpc_cf_stack_name}\":"
        aws cloudformation describe-stacks --stack-name "${vpc_cf_stack_name}" &>/dev/null
        if [[ $? -eq 0 ]] ;then
            cf_wait "${vpc_cf_stack_name}"
            echo
            cf_export_all "${vpc_cf_stack_name}"
            echo
            case "${orchestrator}" in
                slurm) private_subnet="${PrimaryPrivateSubnet}" ;;
                eks)   private_subnet="${PrivateSubnet1}" ;;
            esac
            cf_az=$(aws ec2 describe-subnets --subnet-ids "${private_subnet}" --query 'Subnets[0].AvailabilityZoneId' --output text)
            if [[ -n ${az} ]] ;then
                echo "You set az=\"${az}\". But the VPC stack \"${vpc_cf_stack_name}\" does exist already. It's deployed in AZ \"${cf_az}\""
                if [[ "${az}" != "${cf_az}" ]] ;then
                    echo "WARNING: the requested AZ differs (\"${az}\") from the AZ retrieved (\"${cf_az}\") from the VPC stack!"
                fi
            else
                echo "We are using the VPC stack \"${vpc_cf_stack_name}\" already deployed in AZ \"${cf_az}\"."
            fi
        else
            if [[ -n ${az} ]] ;then
                vpc_stack_deploy
            else
                echo "The VPC stack \"${vpc_cf_stack_name}\" does not exist yet, you need to set the \"az\" variable in this script."
            fi
        fi
    fi
}

# Checking about the Observability stack ${observability_cf_stack_name} and deploys it if needed
check_obs_stack_slurm(){
    if [[ ${observability_cf_stack_name} ]] ;then
        pecho "Checking about the Observability stack \"${observability_cf_stack_name}\":"
        aws cloudformation describe-stacks --stack-name "${observability_cf_stack_name}" &>/dev/null
        if [[ $? -eq 0  ]] ;then
            echo "The Observability stack \"${observability_cf_stack_name}\" is deployed."
        else
            echo "Deploying the Observability stack \"${observability_cf_stack_name}\""
            run aws cloudformation create-stack \
                --capabilities CAPABILITY_NAMED_IAM \
                --stack-name "${observability_cf_stack_name}" \
                --template-url "${observability_cf_stack_url}"
        fi
    fi
}
 
# future, not working yet
grafana_import_dashboard(){
    cf_wait "${observability_cf_stack_name}"
    cf_export_all "${observability_cf_stack_name}"
    # AMPRemoteWriteURL
    # GrafanWorkspaceURL
    # https://grafana.com/grafana/dashboards/4323-slurm-dashboard/
    # https://grafana.com/grafana/dashboards/1860-node-exporter-full/
    # https://grafana.com/grafana/dashboards/12239-nvidia-dcgm-exporter-dashboard/
    # https://grafana.com/grafana/dashboards/20579-efa-metrics-dev/
    # https://grafana.com/grafana/dashboards/20906-fsx-lustre/
    # AWS Data Sources -- Data Source -- CloudWatch and Prometheus with Region
    # https://g-xxx.grafana-workspace.us-west-2.amazonaws.com/a/aws-datasource-provisioner-app/?tab=datasources&id=prometheus
    # https://g-xxx.grafana-workspace.us-west-2.amazonaws.com/a/aws-datasource-provisioner-app/?tab=datasources&id=cloudwatch
}

# Generate environement variables based on inputs and CloudFormation stack outputs
init_env(){
    pecho "Generate environement variables based on inputs and CloudFormation stack outputs:"
    # export role_arn="arn:aws:iam::${account_id}:role/${role_name}"
    run export role_name=$(basename "${AmazonSagemakerClusterExecutionRoleArn}")
    run export SourceS3Uri="s3://${AmazonS3BucketName}/src"
}

# install awscli since the last version is usually required to use the last update from SMHP improvements
install_awscli(){
    pecho "Installing/Updating the AWS CLI"
    echo "Pre-update: $(aws --version)"
    curl -s "${awscli_url}" -o "${awscli_pkg}"
    rm -rf ./aws
    unzip "${awscli_pkg}" > /dev/null
    # ./aws/install --help
    # -i, --install-dir <path> # default: /usr/local/aws-cli
    # -b, --bin-dir <path> # default: /usr/local/bin
    sudo ./aws/install --update > /dev/null
    rm -rf ./aws
    echo "Post-update: $(aws --version)"
}

# checking quotas for instances and and EBS size per instances
check_quota(){
    # no action(s) due to API throttling risk
    local quota_file="sagemaker.quota"
    aws service-quotas list-service-quotas --service-code sagemaker \
        --query 'Quotas[].{Name:QuotaName,Value:Value,Metric:UsageMetric.MetricDimensions.Resource,Code:QuotaCode}' \
        --output text | tr " " "_" > ${quota_file}
    
    pecho "Checking your Quotas for SageMaker EBS"
    grep "cluster/ebs_per_instance_max" < ${quota_file}
    
    pecho "Checking your Quotas for SageMaker instances used"
    for itype in $(sort -u <<< $( tr ' ' '\n' <<< ${instances_types})) ;do
        grep "cluster/${itype}" < ${quota_file}
    done | column -t

}

# adding required policies for the observability stack
obs_enable_iam_hp_role(){
    pecho "Adding Observability policies to the role \"${role_name}\""
    run aws iam attach-role-policy --role-name ${role_name} --policy-arn arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess
    run aws iam attach-role-policy --role-name ${role_name} --policy-arn arn:aws:iam::aws:policy/AWSCloudFormationReadOnlyAccess

    pecho "Checking policies of the role \"${role_name}\""
    run aws iam list-attached-role-policies --role-name ${role_name} --query 'AttachedPolicies[].PolicyName'
    run aws iam list-role-policies --role-name ${role_name}
}

# clone a specific GitHub repo
gh_clone(){
    local repo="${1}"
    local folder="$(basename "${repo}")"

    pecho "Cloning the GitHub repository \"${repo}\":"
    rm -rf "./${folder}"
    # run git clone --depth=1 "https://github.com/${repo}"
    run git clone "https://github.com/${repo}"
}

# Life Cycle Script option swap to add a feature for example
lcs_option_swap(){
    local key="${1}"
    local val="${2}"
    local conf="config.py"
    pecho "Swapping \"${key}\" to \"${val}\" in Life Cycle Script configuration file \"${conf}\""
    echo "Before: $(grep "${key}.*=" ${lcs_path}/${conf})"
    sed -i "${lcs_path}/${conf}" -e "s#${key} =.*#${key} = ${val}#g"
    echo "After: $(grep "${key}.*=" ${lcs_path}/${conf})"
}

# Generating the HyperPod Slurm cluster configuration file
gen_cluster_conf_slurm(){
    local cluster_conf="${1}" # smhp_config
    # needs bash arrays: controller, login, worker
    pecho "Generating the HyperPod Slurm cluster configuration ${cluster_conf}"

    cat > ${cluster_conf} << EOL
{
    "ClusterName": "${SMHP_ClusterName}",
    "InstanceGroups": [
EOL

    for itype in "${!controller[@]}" ;do
        icount=1 # only one
        cat >> ${cluster_conf} << EOL
      {
        "InstanceGroupName": "controller-machine",
        "InstanceType": "${itype}",
        "InstanceStorageConfigs": [
          {
            "EbsVolumeConfig": {
              "VolumeSizeInGB": ${VolumeSizeInGB}
            }
          }
        ],
        "InstanceCount": ${icount},
        "LifeCycleConfig": {
          "SourceS3Uri": "${SourceS3Uri}",
          "OnCreate": "on_create.sh"
        },
        "ExecutionRole": "${AmazonSagemakerClusterExecutionRoleArn}",
        "ThreadsPerCore": 2
      },
EOL
        break # only one Instance Type
    done

    group=1
    for itype in "${!login[@]}" ;do
        icount="${login[${itype}]}"
        cat >> ${cluster_conf} << EOL
      {
        "InstanceGroupName": "login-group",
        "InstanceType": "${itype}",
        "InstanceStorageConfigs": [
          {
            "EbsVolumeConfig": {
              "VolumeSizeInGB": ${VolumeSizeInGB}
            }
          }
        ],
        "InstanceCount": ${icount},
        "LifeCycleConfig": {
          "SourceS3Uri": "${SourceS3Uri}",
          "OnCreate": "on_create.sh"
        },
        "ExecutionRole": "${AmazonSagemakerClusterExecutionRoleArn}",
        "ThreadsPerCore": 2
      },
EOL
        # "InstanceGroupName": "login-group-${group}",
        ((group++))
    done

    group=1
    for itype in "${!worker[@]}" ;do
        icount="${worker[${itype}]}"
        if [[ $group -ge 2 ]] ;then echo '      ,' >> ${cluster_conf} ;fi
        cat >> ${cluster_conf} << EOL
      {
        "InstanceGroupName": "worker-group-${group}",
        "InstanceType": "${itype}",
        "InstanceCount": ${icount},
        "InstanceStorageConfigs": [
          {
            "EbsVolumeConfig": {
              "VolumeSizeInGB": ${VolumeSizeInGB}
            }
          }
        ],
        "LifeCycleConfig": {
          "SourceS3Uri": "${SourceS3Uri}",
          "OnCreate": "on_create.sh"
        },
        "ExecutionRole": "${AmazonSagemakerClusterExecutionRoleArn}",
        "ThreadsPerCore": 1
      }
EOL
        ((group++))
    done
    echo '    ],' >> ${cluster_conf}

    if [[ ${#tag[@]} -ge 1 ]] ;then
        echo '    "Tags": [' >> ${cluster_conf}
        group=1
        for key in "${!tag[@]}" ;do
            val="${tag[${key}]}"
            if [[ $group -ge 2 ]] ;then echo '      ,' >> ${cluster_conf} ;fi
            cat >> ${cluster_conf} << EOL
      {
      "Key": "${key}",
      "Value": "${val}"
      }
EOL
            ((group++))
        done
        echo '     ],' >> ${cluster_conf}
    fi

    cat >> ${cluster_conf} << EOL
    "VpcConfig": {
      "SecurityGroupIds": ["${SecurityGroup}"],
      "Subnets":["${PrimaryPrivateSubnet}"]
    }
}
EOL
}

# Generating the HyperPod cluster provisioning file
gen_cluster_provisioning_slurm(){
    local provisioning_conf="${1}" # smhp_provisioning
    # needs bash arrays: controller, login, worker
    pecho "Generating the HyperPod cluster provisioning ${provisioning_conf}"

    cat > ${provisioning_conf} << EOL
{
  "version": "1.0.0",
  "workload_manager": "slurm",
  "controller_group": "controller-machine",
EOL

    if [[ ${#login[@]} -ge 1 ]] ;then
        echo '  "login_group": "login-group",' >> ${provisioning_conf}
        #     echo '  "login_groups": [' >> ${smhp_provisioning}
        #     group=1
        #     for itype in "${!login[@]}" ;do
        #         if [[ $group -ge 2 ]] ;then echo '    ,' >> ${smhp_provisioning} ;fi
        #         cat >> ${smhp_provisioning} << EOL
        #     {
        #       "instance_group_name": "login-group-${group}"
        #     }
        # EOL
        #       # "partition_name": "${itype}"
        #     ((group++))
        #     done
    fi
    # echo "  ]," >> ${smhp_provisioning}

    echo '  "worker_groups": [' >> ${provisioning_conf}
    group=1
    for itype in "${!worker[@]}" ;do
        if [[ $group -ge 2 ]] ;then echo '    ,' >> ${provisioning_conf} ;fi
        cat >> ${provisioning_conf} << EOL
    {
      "instance_group_name": "worker-group-${group}",
      "partition_name": "${itype}"
    }
EOL
        ((group++))
    done
    echo "  ]," >> ${provisioning_conf}

    cat >> ${provisioning_conf} << EOL
  "fsx_dns_name": "${FSxLustreFilesystemDNSname}",
  "fsx_mountname": "${FSxLustreFilesystemMountname}"
}
EOL
}

# install a local python venv to validate the conf produced
install_boto_venv(){
    local venv="${1}" # venv_smhp
    pecho "Installing Python3 boto3 in \"${venv}\""

    rm -rf "${venv}"
    python3 -m venv "${venv}"
    source ${venv}/bin/activate
    python3 -m pip install --upgrade pip > /dev/null
    python3 -m pip install --upgrade boto3 > /dev/null
    python3 -m pip install --upgrade jsonschema > /dev/null
    deactivate
}

# validate the conf produced
validate_slurm_config(){
    source ${venv_smhp}/bin/activate
    pecho "Validating the configuration files:"
    run_spe python3 ${gh_adt_dir}/1.architectures/5.sagemaker-hyperpod/validate-config.py \
        --cluster-config ${smhp_config} \
        --provisioning-parameters ${smhp_provisioning}
    deactivate
}

# Uploading Life Cycle Scripts and configuration to the S3 bucket
upload_lcs_slurm(){
    pecho "Uploading Life Cycle Scripts and configuration to the S3 bucket \"${SourceS3Uri}\""
    # run "aws s3 rm ${SourceS3Uri} --recursive > /dev/null" # WARNING
    run "aws s3 cp ${smhp_provisioning} ${SourceS3Uri}/ > /dev/null"
    run "aws s3 cp --recursive ${gh_adt_dir}/1.architectures/5.sagemaker-hyperpod/LifecycleScripts/base-config/ ${SourceS3Uri} > /dev/null"
    run aws s3 ls ${SourceS3Uri} --recursive --summarize --human-readable

    pecho "Checking \"${smhp_provisioning}\" upload:"
    remote="$(aws s3 cp ${SourceS3Uri}/${smhp_provisioning} - | md5sum)"
    loc="$(cat ${smhp_provisioning} | md5sum)"
    if [[ "${remote}" == "${loc}" ]] ;then
        echo "\"${smhp_provisioning}\" successfully uploaded."
    else
        echo "\"${smhp_provisioning}\" upload error, aborting."
        exit 1
    fi
}

# Trigger the HyperPod cluster creation
cluster_create(){
    pecho "Trigger the HyperPod cluster creation"
    date
    run aws sagemaker create-cluster --cli-input-json file://${smhp_config} --output text
    # --region ${region}

}

# Waiting on the HyperPod cluster creation
cluster_wait(){
    echo -n "Waiting on the HyperPod cluster \"${SMHP_ClusterName}\" to be ready..."
    while true ;do
        status=$(aws sagemaker describe-cluster --cluster-name "${SMHP_ClusterName}" | jq -r .ClusterStatus)
        case "${status}" in
            "Creating")
                echo -n "."
                sleep 5
                ;;
            "Failed")
                echo
                echo "the HyperPod cluster \"${SMHP_ClusterName}\" status is \"$status\""
                date
                aws sagemaker describe-cluster --cluster-name "${SMHP_ClusterName}" | jq -r .FailureMessage
                echo
                pecho "Deleting \"${SMHP_ClusterName}\":"
                run aws sagemaker delete-cluster --cluster-name "${SMHP_ClusterName}"
                exit 1
                break
                ;;
            "RollingBack")
                echo
                echo "the HyperPod cluster \"${SMHP_ClusterName}\" status is \"$status\""
                date
                run 'aws sagemaker describe-cluster --cluster-name "${SMHP_ClusterName}" | jq -r .FailureMessage'
                echo
                echo "Once the cluster will be in \"Failed\" status, you can delete it with:"
                echo "aws sagemaker delete-cluster --cluster-name \"${SMHP_ClusterName}\""
                exit 1
                break
                ;;
            *|"InService")
                echo
                echo "the HyperPod cluster \"${SMHP_ClusterName}\" status is \"$status\""
                date
                smhp_list
                break
                ;;
        esac
    done
}

# revert the awscli region conf setting
close_env(){
    pecho "Reversing back to your previous configuration "
    cd "${pwd_previous}"
    run aws configure set region ${region_previous} # revert client environment modification
}

# preparing for SSH/SSM to clusters instances
gen_ssm_cli_slurm(){
    local cn="${1}" # SMHP_ClusterName

    cluster_id=$(aws sagemaker describe-cluster --cluster-name "${cn}" | jq -r '.ClusterArn' | awk -F/ '{gsub(/"/, "", $NF); print $NF}')
    for node_group in $(aws sagemaker describe-cluster --cluster-name "${cn}" | jq -r ".InstanceGroups[].InstanceGroupName") ;do
        node_group_list="$(aws sagemaker list-cluster-nodes --cluster-name "${cn}" --instance-group-name-contains "${node_group}" | jq -r '.ClusterNodeSummaries[].InstanceId')"
        echo "For ${node_group} ($(echo ${node_group_list} | wc -w) nodes):"
        for instance_id in ${node_group_list} ;do
            cmd="aws ssm start-session --target sagemaker-cluster:${cluster_id}_${node_group}-${instance_id}"
            echo "    ${cmd}"
        done
    done

    pecho "Getting \"easy-ssh.sh\""
    run curl -s -O https://raw.githubusercontent.com/${gh_adt_url}/main/1.architectures/5.sagemaker-hyperpod/easy-ssh.sh
    chmod +x easy-ssh.sh
    echo "you can use ./easy-ssh.sh -c controller-machine ${cn}"
}


# EKS only - Install kubectl
install_kubectl(){
    local cmd="kubectl"
    pecho "Install ${cmd}"

    curl -s -O "${kubectl_url}"
    chmod +x ./${cmd}
    sudo cp ./${cmd} ${bin_dir}/${cmd}
}

# EKS only - Install eksctl
install_eksctl(){
    local arch=$(uname -m)
    case ${arch} in
        armv5*)  arch="armv5" ;;
        armv6*)  arch="armv6" ;;
        armv7*)  arch="arm"   ;;
        aarch64) arch="arm64" ;;
        x86)     arch="386"   ;;
        x86_64)  arch="amd64" ;;
        i686)    arch="386"   ;;
        i386)    arch="386"   ;;
    esac
    # local arch="amd64" # for ARM systems, set arch to: `arm64`, `armv6` or `armv7`
    local platform="$(uname -s)_${arch}"
    pecho "Install eksctl ${platform}"

    curl -sLO "${eksctl_url}/eksctl_${platform}.tar.gz"
    # (Optional) Verify checksum
    curl -sL "${eksctl_url}/eksctl_checksums.txt" | grep ${platform} | sha256sum --check
    tar -xzf eksctl_${platform}.tar.gz -C ${install_dir}/ && rm eksctl_${platform}.tar.gz
    sudo mv ${install_dir}/eksctl ${bin_dir}/
}

# EKS only - Install Helm
install_helm(){
    export HELM_INSTALL_DIR="${bin_dir}"
    local script="get_helm.sh"
    pecho "Install helm"

    curl -fsSL -o ${script} "${helm_url}"
    chmod 700 ${script}
    ./${script}
    # rm -f ${script}
}

# EKS only - Adding policy ${smhp_eks_policy_name} to ${role_user_name}
eks_hp_enable_iam_user_role(){
    local policy_file="hyperpod-eks-policy.json"
    pecho "Adding policy \"${smhp_eks_policy_name}\" to \"${role_user_name}\""
    
    cat > ${policy_file} << EOL
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "${AmazonSagemakerClusterExecutionRoleArn}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sagemaker:CreateCluster",
                "sagemaker:DeleteCluster",
                "sagemaker:DescribeCluster",
                "sagemaker:DescribeCluterNode",
                "sagemaker:ListClusterNodes",
                "sagemaker:ListClusters",
                "sagemaker:UpdateCluster",
                "sagemaker:UpdateClusterSoftware",
                "sagemaker:DeleteClusterNodes",
                "eks:DescribeCluster",
                "eks:CreateAccessEntry",
                "eks:DescribeAccessEntry",
                "eks:DeleteAccessEntry",
                "eks:AssociateAccessPolicy",
                "iam:CreateServiceLinkedRole"
            ],
            "Resource": "*"
        }
    ]
}
EOL

    aws iam create-policy \
        --policy-name "${smhp_eks_policy_name}" \
        --policy-document file://${policy_file}

    aws iam attach-role-policy \
        --policy-arn "arn:aws:iam::${account_id}:policy/${smhp_eks_policy_name}" \
        --role-name "${role_user_name}"
}

# EKS only - Upload the OnCreate script to ${SourceS3Uri}
upload_lcs_eks(){
    pecho "Upload the OnCreate LCS to ${SourceS3Uri}"

    local OnCreate="on_create.sh"
    curl -s "${lcs_eks_path}" --output "${OnCreate}"
    aws s3 cp "${OnCreate}" "${SourceS3Uri}/"
}

# EKS only - Configure the EKS Cluster and add the required access-entry and access-policy
eks_configure(){
    pecho "Configure the EKS Cluster"

    run aws eks update-kubeconfig --name "${ClusterName}"

    ls -lh ${HOME}/.kube/config
    cat ${HOME}/.kube/config

    run kubectl config current-context

    pecho "Create additional access entries, to give your IAM principal access your EKS cluster, with an access policy and its scope"

    aws eks create-access-entry --cluster-name ${ClusterName} --principal-arn ${role_user_arn} --type STANDARD
    # --username ${role_user_name}
    aws eks list-access-entries --cluster-name ${ClusterName}
    aws eks associate-access-policy \
        --cluster-name ${ClusterName} --principal-arn ${role_user_arn} \
        --access-scope type=cluster --policy-arn "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    aws eks list-associated-access-policies --cluster-name ${ClusterName} --principal-arn ${role_user_arn}
}

# EKS only - Install the Helm Chart, update dependencies, dry run, deploy and list them, and locally test the helm chart
eks_install_depencies(){
    pecho "Install the Helm Chart, update dependencies, dry run, deploy and list them, and locally test the helm chart"

    gh_clone "${gh_smhpcli_url}"
    cd "${gh_smhpcli_dir}/helm_chart"
    helm lint HyperPodHelmChart
    helm dependencies update HyperPodHelmChart
    helm install dependencies HyperPodHelmChart --dry-run
    helm install dependencies HyperPodHelmChart --namespace kube-system
    run helm list --namespace kube-system
    cd -
    
    cd "${gh_smhpcli_dir}"
    source ${venv_smhp}/bin/activate
    pip install .
    which hyperpod
    deactivate
    cd -
    
    # https://catalog.ngc.nvidia.com/orgs/nvidia/teams/devtools/helm-charts/devtools-sidecar-injector
    # NVIDIA DevTools Sidecar Injector
    # helm install -f custom_values.yaml devtools-sidecar-injector "${nsight_sidecar}"
    
}

# EKS only - Display everything which has been installed in EKS
eks_list(){
    pecho "Display everything which has been installed in EKS"

    run kubectl get svc
    run kubectl get ds health-monitoring-agent -n aws-hyperpod
    run kubectl get ds dependencies-nvidia-device-plugin -n kube-system
    run kubectl get ds neuron-device-plugin-daemonset -n kube-system
    run kubectl get ds dependencies-aws-efa-k8s-device-plugin -n kube-system
    run kubectl get deploy dependencies-training-operators -n kubeflow
    run kubectl get crd | grep kubeflow
    run kubectl get deploy dependencies-mpi-operator -n kube-system
    run kubectl get crd mpijobs.kubeflow.org -n kubeflow -o jsonpath='{.status.storedVersions[]}'
    run kubectl get priorityclass
    run kubectl describe pvc fsx-claim
    run kubectl get storageclass
    run kubectl get nodes -o wide
    run helm list --namespace kube-system
    run kubectl get namespaces
}

# Generating the HyperPod EKS cluster configuration
gen_cluster_conf_eks(){
    local cluster_conf="${1}" # smhp_config
    pecho "Generating the HyperPod EKS cluster configuration ${cluster_conf}"

    cat > ${cluster_conf} << EOL
{
    "ClusterName": "${SMHP_ClusterName}",
    "Orchestrator": {
      "Eks":
      {
        "ClusterArn": "${ClusterArn}"
      }
    },
    "InstanceGroups": [
EOL

    group=1
    for itype in "${!worker[@]}" ;do
        icount="${worker[${itype}]}"
        if [[ $group -ge 2 ]] ;then echo '      ,' >> ${cluster_conf} ;fi
        cat >> ${cluster_conf} << EOL
      {
        "InstanceGroupName": "worker-group-${group}",
        "InstanceType": "${itype}",
        "InstanceCount": ${icount},
        "InstanceStorageConfigs": [
          {
            "EbsVolumeConfig": {
              "VolumeSizeInGB": ${VolumeSizeInGB}
            }
          }
        ],
        "LifeCycleConfig": {
          "SourceS3Uri": "${SourceS3Uri}",
          "OnCreate": "on_create.sh"
        },
        "ExecutionRole": "${AmazonSagemakerClusterExecutionRoleArn}",
        "ThreadsPerCore": 1
EOL
        if [[ "${itype}" =~ ml\.[gp][0-9]+[a-z]*\.[0-9]+xlarge ]] ;then
            echo '        "OnStartDeepHealthChecks": ["InstanceStress", "InstanceConnectivity"]' >> ${cluster_conf}
        fi
        echo '      }' >> ${cluster_conf}
        ((group++))
    done
    echo '    ],' >> ${cluster_conf}

    if [[ ${#tag[@]} -ge 1 ]] ;then
        echo '    "Tags": [' >> ${cluster_conf}
        group=1
        for key in "${!tag[@]}" ;do
            val="${tag[${key}]}"
            if [[ $group -ge 2 ]] ;then echo '      ,' >> ${cluster_conf} ;fi
            cat >> ${cluster_conf} << EOL
      {
      "Key": "${key}",
      "Value": "${val}"
      }
EOL
            ((group++))
        done
        echo '     ],' >> ${cluster_conf}
    fi

    cat >> ${cluster_conf} << EOL
    "VpcConfig": {
      "SecurityGroupIds": ["${NoIngressSecurityGroup}"],
      "Subnets":["${PrivateSubnet1}"]
    },
    "NodeRecovery": "${NodeRecovery}"
}
EOL
}

# EKS only - Install the Amazon FSx for Lustre CSI Driver fsx-csi-controller
eks_setup_fsxl_csi(){
    local driver="$(basename "${aws_fsx_csi_url}")" # aws-fsx-csi-driver
    local role_eks_fsxl="AmazonEKSFSxLustreCSIDriverFullAccess"
    local role_sa_arn=$(aws iam get-role --role-name "${role_eks_fsxl}" --query 'Role.Arn' --output text)
    local fsx_csi="fsx-csi-controller"
    local sa_name="${fsx_csi}-sa"

    pecho "Install the Amazon FSx for Lustre CSI Driver fsx-csi-controller"

    eksctl utils associate-iam-oidc-provider --cluster "${ClusterName}" --approve
    helm repo add "${driver}" "${aws_fsx_csi_url}"
    helm repo update
    helm upgrade --install "${driver}" "${driver}/${driver}" --namespace kube-system

    eksctl create iamserviceaccount \
        --name "${sa_name}" \
        --override-existing-serviceaccounts \
        --namespace kube-system \
        --cluster "${ClusterName}" \
        --attach-policy-arn "arn:aws:iam::aws:policy/AmazonFSxFullAccess" \
        --approve \
        --role-name "${role_eks_fsxl}"


    kubectl annotate serviceaccount -n kube-system "${sa_name}" \
        eks.amazonaws.com/role-arn=${role_sa_arn} --overwrite=true

    kubectl get serviceaccount -n kube-system "${sa_name}" -oyaml
    kubectl rollout restart deployment "${fsx_csi}" -n kube-system
}

# EKS only - Install FSx for Lustre CSI Driver Dynamic Provisioning with StorageClass fsx-sc provisioner: fsx.csi.aws.com and PersistentVolumeClaim fsx-claim
eks_gen_fsxl_csi_dynamic(){
    sc_fsxl_conf="storageclass.yaml"
    pvc_fsxl_conf="pvc.yaml"
    pecho "Install FSx for Lustre CSI Driver Dynamic Provisioning with StorageClass fsx-sc provisioner: fsx.csi.aws.com and PersistentVolumeClaim fsx-claim"

    cat << EOF > ${sc_fsxl_conf}
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: fsx-sc
provisioner: fsx.csi.aws.com
parameters:
  subnetId: ${PrivateSubnet1}
  securityGroupIds: ${NoIngressSecurityGroup}
  deploymentType: PERSISTENT_2
  automaticBackupRetentionDays: "0"
  copyTagsToBackups: "true"
  perUnitStorageThroughput: "250"
  dataCompressionType: "LZ4"
  fileSystemTypeVersion: "2.12"
mountOptions:
  - flock
EOF

    cat <<EOF> ${pvc_fsxl_conf}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fsx-claim
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: fsx-sc
  resources:
    requests:
      storage: 1200Gi
EOF

    kubectl apply -f ${sc_fsxl_conf}
    kubectl apply -f ${pvc_fsxl_conf}

}

# TBD
# eks_gen_fsxl_csi_static(){
#     pecho "FSx for Lustre CSI Driver Static Provisioning"
# }


# main for SMHP Slurm
main_slurm(){

    init_env_pre

    check_quota
    smhp_list

    smhp_check_cluster "${SMHP_ClusterName}"
    vpc_stack_check_deploy
    check_obs_stack_slurm

    init_env

    obs_enable_iam_hp_role
    # grafana_import_dashboard &

    install_awscli
    gh_clone "${gh_adt_url}"

    # lcs_option_swap enable_mount_s3 True
    # lcs_option_swap data_bucket \"${AmazonS3BucketName}\"
    lcs_option_swap "enable_observability" "True"

    gen_cluster_conf_slurm "${smhp_config}"
    gen_cluster_provisioning_slurm "${smhp_provisioning}"

    install_boto_venv "${venv_smhp}"
    validate_slurm_config
    
    upload_lcs_slurm

    cluster_create
    cluster_wait

    # pecho "Wait on previous background fonctions..." ; wait ; echo "...all done."

    gen_ssm_cli_slurm "${SMHP_ClusterName}"
    close_env
}

# main for SMHP EKS
main_eks(){

    init_env_pre

    check_quota
    smhp_list

    smhp_check_cluster "${SMHP_ClusterName}"
    vpc_stack_check_deploy

    init_env

    install_awscli
    install_kubectl
    install_eksctl
    install_helm

    eks_hp_enable_iam_user_role
    upload_lcs_eks
    eks_configure
    eks_install_depencies
    gen_cluster_conf_eks "${smhp_config}"
    eks_setup_fsxl_csi
    eks_gen_fsxl_csi_dynamic
    # eks_gen_fsxl_csi_static
    
    eks_list
    cluster_create
    cluster_wait
    
    gen_ssm_cli_slurm "${SMHP_ClusterName}"
    close_env
}

# main
main(){
    case "${orchestrator}" in
        slurm)
            main_slurm $@
            ;;
        eks)
            main_eks $@
            ;;
        *)
            pecho "ERROR: unknown orchestrator \"${orchestrator}\""
            exit 1
            ;;
    esac
}


main $@

exit






