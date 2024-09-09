# AWS SageMaker HyperPod Distributed Training Reference Architectures


> [!IMPORTANT]  
> 🚨 We recommend following the official [Amazon SageMaker HyperPod Workshop](https://catalog.workshops.aws/sagemaker-hyperpod/en-US) to deploy clusters, which contains detailed instructions and latest best-practices.

## 1. Architectures

Amazon SageMaker HyperPod is a managed service that makes it easier for you to train foundation models without interruptions or delays. It provides resilient and persistent clusters for large scale deep learning training of foundation models on long-running compute clusters. With HyperPod integration with Amazon EKS, customers can associate a HyperPod cluster with an EKS cluster and manage ML workloads using the HyperPod cluster nodes as Kubernetes worker nodes, all through the Kubernetes control plane on the EKS cluster.


The example that follows describes the process of setting up a SageMaker HyperPod cluster with EKS.

## 2. Prerequisites

### 2.1. Install AWS CLI

Before creating a cluster, we need to install the latest [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), you'll need version 2.14.3 as a minimum to run the SageMaker HyperPod commands:

### 2.2. Install Kubectl

We will need to setup kubectlto interact with the EKS cluster Kubernetes API server. The following commands correspond with Linux installations. See the Kubernetes documentation for steps on how to install kubectl on other environments.

```bash
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.29.3/2024-04-19/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
```

### 2.3 Install Eksctl

You will use eksctl to create an IAM OIDC provider for your EKS cluster and use it to install additional addons. The following commands correspond with Unix installations. See the eksctl documentation for alternative instilation options.

```bash
# for ARM systems, set ARCH to: `arm64`, `armv6` or `armv7`
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH

curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"

# (Optional) Verify checksum
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check

tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz

sudo mv /tmp/eksctl /usr/local/bin
```

### 2.4 Deploy the cloudformation stack (optional)

We have provided an cloudformation template that helps you to setup vpc, subnets, EKS cluster and necessary SageMaker Permissions. The template can be used in 3 scenarios
1. **Full Deployment** - Use full deployment mode if you want to create a new VPC and EKS cluster. On the template set  ```CreateEKSCluster to true```
2. **Integrative Deployment** - Use integrative deployment mode if you want to use your own VPC and EKS cluster, but need to create an additional /16 CIDR block, a private subnet, and a security group for the SageMaker HyperPod Cluster. For this option 
Set the following parameters accordingly if you want to use integrative deployment mode.

    * Set CreateEKSCluster to false
    * Set CreateSubnet to true
    * Provide the AvailabilityZoneId (usw2-az2 for the us-west-2 region by default). Update this parameter based on your region and the Availability Zone that you have accelerated compute capacity in. An additional CIDR block will be added to your VPC with a /16 private subnet in the specified Availability Zone. This private subnet will be used to deploy the HyperPod cross-account elastic network intefaces (ENIs), which give you access to the HyperPod capacity you deploy.
    * Provide the NatGatewayId. This parameter is used to create a route to the internet from the newly create private subnet
    * Provide the SecurityGroupId. This parameter is used to identify the security group associated with your EKS cluster so that a newly created security group can be configured with rules to allow communication with the EKS control plane.
    * Provide the VpcId. This parameter is used to attach an additional /16 CIDR block (10.1.0.0/16 by default) to your existing VPC.
    * Provide the PrivateSubnet1CIDR. This parameter is used to specify the desired range to use for the additional /16 CIDR block and private subnet (10.1.0.0/16 by default). Please configure a CIDR range that does not overlap with your existing VPC.

3. **Minimal Deployment** - Use minimal deployment mode if you want to use your own VPC and EKS cluster, and you want to manage the subnet and security group configurations in your environment by yourself. This optional only creates SageMaker HyperPod specific stuff like role, bucket needed for cluster creation. 
Set the following parameters accordingly if you want to use minimal deployment mode.

    * Set CreateEKSCluster to false
    * Set CreateSubnet to false

We can launch the cloudformation using the below . Depending on the deployment option that works for you , update the parameters in the stack accordingly.

You can create a VPC using the configuration in [hyperpod-eks-full-stack.yaml](./hyperpod-eks-full-stack.yaml). Which is also available via [<kbd> <br> 1-Click Deploy 🚀 <br> </kbd>](https://us-west-2.console.aws.amazon.com/cloudformation/home?region=us-west-2#/stacks/quickcreate?templateURL=https://awsome-distributed-training.s3.amazonaws.com/templates/Vpc.yaml&stackName=SageMakerVPC)

### 2.5 Connect to EKS cluster 

Once you created the Amazon EKS cluster,  We'll reference this EKS cluster as the orchestrator of the HyperPod compute nodes. 

From the above cloud formation , an [AccessEntry](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-eks-accessentry.html) for the EKS cluster with [AmazonEKSClusterAdminPolicy](https://docs.aws.amazon.com/eks/latest/userguide/access-policies.html#access-policy-permissions) permissions has been automatically created for you. 

Run the [aws eks update-kubeconfig](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/eks/update-kubeconfig.html) command to upade your local kubeconfig file (located at `~/.kube/config`) with the credentials and configuration needed to connect to your EKS cluster using the `kubectl` command.  

```bash
aws eks update-kubeconfig --name $EKS_CLUSTER_NAME
```

You can verify that you are connected to the EKS cluster by running this commands: 
```bash 
kubectl config current-context 
```
```
arn:aws:eks:us-west-2:xxxxxxxxxxxx:cluster/hyperpod-eks-cluster
```
```bash
kubectl get svc
```
```
NAME             TYPE        CLUSTER-IP   EXTERNAL-IP PORT(S)   AGE
svc/kubernetes   ClusterIP   10.100.0.1   <none>      443/TCP   1m
```

### 2.6 Install Dependencies

The HyperPod team provides a Helm chart package, which bundles key dependencies and associated permission configurations. This package contains dependencies such as Health Monitoring Agent, Nvidia device plugins, EFA device plugin, Neuron Device plugin. Below steps shows how to install the helm chart

#### Clone the Repo 

(Update for GA)
```bash
git clone ssh://git.amazon.com/pkg/HyperpodCLI
cd HyperpodCLI/src/hyperpod_cli/helm_chart
```

#### Install the Helm Chart

Locally test the helm chart: 
```bash
helm lint HyperPodHelmChart
```
Update the dependencies: 
```bash 
helm dependencies update HyperPodHelmChart
```
Conduct a dry run: 
```bash 
helm install dependencies HyperPodHelmChart --dry-run
```
Deploy the helm chart: 
```bash 
helm install dependencies HyperPodHelmChart --namespace kube-system
```


## 3. Create SageMaker HyperPod cluster

Now that we have all our infrastructure in place, we can create a cluster. 

We need to setup few environment variables required for creating cluster. You will need to set the below environment parameters accordingly as per your requirement. 

```bash
export ACCEL_INSTANCE_TYPE=ml.g5.12xlarge #change this
export AWS_REGION=us-west-2 #change this
export ACCEL_COUNT=1 #change this
export ACCEL_VOLUME_SIZE=500 #the size in GB of the EBS volume attached to the compute node.
export GEN_INTANCE_TYPE= ml.m5.2xlarge	#The general purpose compute instance type you want to use
export GEN_COUNT=1	#The number of general purpose compute nodes you want to deploy
export GEN_VOLUME_SIZE=500 #The size in GB of the EBS volume attached to the general purpose compute nodes
export NODE_RECOVEY=AUTOMATIC 

```

 If you have used the full deployment option while deploying cloud formation you can use the helper script([create_config.sh](./create_config.sh)) to retreive all the required. 

 If you used Integrative Deployment Mode set the below parameters

```bash
export EKS_CLUSTER_ARN=<YOUR_EKS_CLUSTER_ARN_HERE>
export EKS_CLUSTER_NAME=<YOUR_EKS_CLUSTER_NAME_HERE>
```

 If you used minimal deployment option you will have to explicitly set the below environment variables 

```bash
export EKS_CLUSTER_ARN=<YOUR_EKS_CLUSTER_ARN_HERE>
export EKS_CLUSTER_NAME=<YOUR_EKS_CLUSTER_NAME_HERE>
export VPC_ID=<YOUR_VPC_ID_HERE>
export SUBNET_ID=<YOUR_SUBNET_ID_HERE>
export SECURITY_GROUP=<YOUR_SECURITY_GROUP_ID_HERE>
```

Once set you can run the create_config.sh to set all the required environment variables.

```bash
export STACK_ID=hyperpod-eks-full-stack # change this accordingly 
bash ./create_config.sh
source env_vars
```


### 3.1 Lifecycle scripts

Lifecycle scripts tell SageMaker HyperPod how to setup your HyperPod cluster. You can use this to install any node level customizations needed for your cluster. We provide a [base configuration](./LifecycleScripts/base-config) to get started. Below is a brief description of what each script is doing.

| Script                       | Description                                                                                                                                    |
|------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| on_create.sh                 | [required] dummy script that is needed to create cluster                                                                           |


For now, let's just use the base configuration provided. Upload the scripts to the bucket you created earlier.
```
aws s3 cp --recursive LifecycleScripts/base-config s3://${BUCKET_NAME}/LifecycleScripts/base-config
```

### 3.2 Cluster configuration

Next we can configure our actual cluster. In this case, we are creating a cluster with 2 Instance Groups. One with ml.m5.2xlarge instance and one with ml.g5.12xlarge instance. 

>Note - You can modify the number of instance groups as per your requirement. It is not mandatory to have 2 instance groups for cluster creation.

Lets start by creating cluster-config.json using the below snippet that uses the environment variables. 

```json
cat > cluster-config.json << EOL
{
    "ClusterName": "ml-cluster",
    "Orchestrator": { 
      "Eks": 
      {
        "ClusterArn": "${EKS_CLUSTER_ARN}"
      }
    },
    "InstanceGroups": [
      {
        "InstanceGroupName": "worker-group-1",
        "InstanceType": "${ACCEL_INSTANCE_TYPE}",
        "InstanceCount": ${ACCEL_COUNT},
        "InstanceStorageConfigs": [
          {
            "EbsVolumeConfig": {
              "VolumeSizeInGB": ${ACCEL_VOLUME_SIZE}
            }
          }
        ],
        "LifeCycleConfig": {
          "SourceS3Uri": "s3://${BUCKET_NAME}",
          "OnCreate": "on_create.sh"
        },
        "ExecutionRole": "${EXECUTION_ROLE}",
        "ThreadsPerCore": 1,
        "OnStartDeepHealthCheck": ["InstanceStress", "InstanceConnectivity"]
      },
      {
        "InstanceGroupName": "worker-group-2",
        "InstanceType": "${GEN_INSTANCE_TYPE}",
        "InstanceCount": ${GEN_COUNT},
        "InstanceStorageConfigs": [
          {
            "EbsVolumeConfig": {
              "VolumeSizeInGB": ${GEN_VOLUME_SIZE}
            }
          }
        ],
        "LifeCycleConfig": {
          "SourceS3Uri": "s3://${BUCKET_NAME}",
          "OnCreate": "on_create.sh"
        },
        "ExecutionRole": "${EXECUTION_ROLE}",
        "ThreadsPerCore": 1
      }
    ],
    "VpcConfig": {
      "SecurityGroupIds": ["$SECURITY_GROUP"],
      "Subnets":["$SUBNET_ID"]
    },
    "NodeRecovery": "${NODE_RECOVERY}"
}
EOL
```

- You can configure up to 20 instance groups under the `InstanceGroups` parameter. 
- For `Orchestrator.Eks.ClusterArn`, specify the ARN of the EKS cluster you want to use as the orchestrator. 
- For `OnStartDeepHealthCheck`, add `InstanceStress` and `InstanceConnectivity` to enable deep health checks. 
- For `NodeRecovery`, specify `Automatic` to enable automatic node recovery. HyperPod replaces or reboots instances (nodes) that fail the basic health or deep health checks (when enabled). 
- For the `VpcConfig` parameter, specify the information of the VPC used in the EKS cluster. The subnets must be private


### 3.3 Launch a new cluster

Now that everything is in place, we can launch our cluster with the below command.


```bash
aws sagemaker create-cluster \
    --cli-input-json file://cluster-config.json \
    --region $AWS_REGION
```

You can see the current state of the cluster with

```bash
aws sagemaker list-clusters \
 --output table \
 --region $AWS_REGION
```

You'll see output similar to the following:

```
-------------------------------------------------------------------------------------------------------------------------------------------------
|                                                                 ListClusters                                                                  |
+-----------------------------------------------------------------------------------------------------------------------------------------------+
||                                                              ClusterSummaries                                                               ||
|+----------------------------------------------------------------+----------------------+----------------+------------------------------------+|
||                           ClusterArn                           |     ClusterName      | ClusterStatus  |           CreationTime             ||
|+----------------------------------------------------------------+----------------------+----------------+------------------------------------+|
||  arn:aws:sagemaker:us-west-2:xxxxxxxxxxxx:cluster/uwme6r18mhic |  ml-cluster          |  Creating     |  2024-07-11T16:30:42.219000-04:00   ||
|+----------------------------------------------------------------+----------------------+----------------+------------------------------------+|
```

### 3.4 SSH into instances in the HyperPod Cluster

To SSH into the instances, you need the cluster id from the cluster arn, instance ID of your node, and instance group name of your controller group. You can your HyperPod cluster ID with

```
aws sagemaker describe-cluster --cluster-name ml-cluster --region us-west-2

{
    "ClusterArn": "arn:aws:sagemaker:us-west-2:123456789012:cluster/2hd31rmi9mde",
    "ClusterName": "ml-cluster",
```

In this case, the cluster ID is `2hd31rmi9mde`

Get your  machine instance ID with

```
aws sagemaker list-cluster-nodes --cluster-name ml-cluster --region us-west-2

{
    "NextToken": "",
    "ClusterNodeSummaries": [
        {
            "InstanceGroupName": "controller-machine",
            "InstanceId": "i-09e7576cbc230c181",
            "InstanceType": "ml.c5.xlarge",
            "LaunchTime": "2023-11-26T15:28:20.665000-08:00",
            "InstanceStatus": {
                "Status": "Running",
                "Message": ""
            }
        },
```

And login with

```
CLUSTER_ID=2hd31rmi9mde
CONTROLLER_GROUP=controller-machine
INSTANCE_ID=i-09e7576cbc230c181
TARGET_ID=sagemaker-cluster:${CLUSTER_ID}_${CONTROLLER_GROUP}-${INSTANCE_ID}
aws ssm start-session --target $TARGET_ID
```

### 3.5 Running workloads on the cluster 

To run workloads on the cluster you can use kubctl ( configured in prerequisities) to interact with the EKS control plane and submit jobs. 

Amazon SageMaker HyperPod also provides a CLI which can be used to manage jobs on the cluster without having to worry about the kubernetes constraints. To setup the CLI follow the below steps. 

-----To be compeleted------

### 3.6 Patching your HyperPod cluster

Run `update-cluster-software` to update existing HyperPod clusters with software and security patches provided by the SageMaker HyperPod service. For more details, see [Update the SageMaker HyperPod platform software of a cluster](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-operate.html#sagemaker-hyperpod-operate-cli-command-update-cluster-software) in the *Amazon SageMaker Developer Guide*.

```
aws sagemaker update-cluster-software --cluster-name ml-cluster --region us-west-2
```

Note that this API replaces the instance root volume and cleans up data in it. You should back up your work before running it.
We've included a script `patching-backup.sh` that can backup and restore the data via Amazon S3.
```
# to backup data to an S3 bucket before patching
sudo bash patching-backup.sh --create <s3-buckup-bucket-path>
# to restore data from an S3 bucket after patching
sudo bash patching-backup.sh --restore <s3-buckup-bucket-path>
```

### 3.7 Deleting your HyperPod cluster

When you're done with your HyperPod cluster, you can delete it down with

```
aws sagemaker delete-cluster --cluster-name ml-cluster --region us-west-2
```