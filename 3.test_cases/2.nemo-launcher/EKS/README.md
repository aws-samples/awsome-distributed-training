# Run the NeMo Framework on Amazon EKS

[NVIDIA NeMo™](https://www.nvidia.com/en-us/ai-data-science/products/nemo/) is an end-to-end, cloud-native enterprise framework for developers to build, customize, and deploy generative AI models with billions of parameters. The NeMo framework provides an accelerated workflow for training with 3D parallelism techniques. It offers a choice of several customization techniques and is optimized for at-scale inference of models for language and image applications, with multi-GPU and multi-node configurations. NeMo makes generative AI model development easy, cost-effective, and fast for enterprises.

In this work we will present a step by step guide to run distributed training workloads on an [Amazon EKS](https://aws.amazon.com/eks/) cluster.

# 0. Prerequisites
We require that to run this workload, you have a 2 node P4de or P5 cluster available with EFA enabled and a [Amazon FSx for Lustre](https://aws.amazon.com/fsx/lustre/) mounted on that cluster. You can follow the steps at [4.amazon-eks](https://github.com/aws-samples/awsome-distributed-training/tree/nemo-on-eks/1.architectures/4.amazon-eks) to create a EFA enabled EKS cluster with P4de nodes. To this end, we provide the cluster creation config in `p4de-cluster-config.yaml`.

This config will create 2 managed node groups, one for the system node `c5.2xlarge` and one `p4de.24xlarge`. Managed node groups will use EKS optimized AMIs.

If you wish to provide a custom AMI, you can create an `unmanaged` node group and specify a custom AMI. To find the AMI id you can follow these [steps](https://docs.aws.amazon.com/eks/latest/userguide/retrieve-ami-id.html). Also, to find more details about the EKS optimized AMI, please see [here](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html#efa-instance-types).

The [Nvidia device plugin for Kubernetes](https://github.com/NVIDIA/k8s-device-plugin) should already be deployed but if not you can do so as follows:

```bash
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.3/nvidia-device-plugin.yml
```

# 1. Deploy the AWS EFA Kubernetes Device Plugin

Once the cluster is created you can install the [AWS EFA Kubernetes Device Plugin](https://github.com/aws/eks-charts/tree/master/stable/aws-efa-k8s-device-plugin) as follows:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm install efa eks/aws-efa-k8s-device-plugin -n kube-system

```

Once this is done, you should see the following pods:
```bash
root@cb9511473ccc:/eks/deployment/efa-device-plugin# k get pods -A
NAMESPACE     NAME                                        READY   STATUS    RESTARTS   AGE
kube-system   aws-efa-k8s-device-plugin-daemonset-78x4q   1/1     Running   0          38m
kube-system   aws-efa-k8s-device-plugin-daemonset-tgfbk   1/1     Running   0          38m
kube-system   aws-node-2fqmn                              2/2     Running   0          10h
kube-system   aws-node-kbjfd                              2/2     Running   0          10h
kube-system   aws-node-pgknw                              2/2     Running   0          10h
kube-system   coredns-9556476b9-888q4                     1/1     Running   0          10h
kube-system   coredns-9556476b9-x2cqq                     1/1     Running   0          10h
kube-system   kube-proxy-67j5j                            1/1     Running   0          10h
kube-system   kube-proxy-hmxpp                            1/1     Running   0          10h
kube-system   kube-proxy-v6c62                            1/1     Running   0          10h
kube-system   nvidia-device-plugin-daemonset-6fz2s        1/1     Running   0          10h
kube-system   nvidia-device-plugin-daemonset-h58n7        1/1     Running   0          10h
kube-system   nvidia-device-plugin-daemonset-vrz2q        1/1     Running   0          10h

```
You can use the [EKS node viewer](https://github.com/awslabs/eks-node-viewer) tool to view nodes and their status in your cluster. Once it is installed, you can simply type `eks-node-viewer` in the console or `nv` in the `aws-do-eks` container to get the following view:

```bash
3 nodes (650m/199290m) 0.3% cpu ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ $82.272/hour | $60058.195/month
21 pods (0 pending 21 running 21 bound)

ip-192-168-120-214.us-west-2.compute.internal cpu ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   4% (8 pods) c5.2xlarge/$0.3400     On-Demand - Ready
ip-192-168-165-37.us-west-2.compute.internal  cpu ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0% (7 pods) p4de.24xlarge/$40.9657 On-Demand - Ready
ip-192-168-164-33.us-west-2.compute.internal  cpu ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0% (6 pods) p4de.24xlarge/$40.9657 On-Demand - Ready
•
←/→ page • q: quit

```

Here the node viewer shows the IP addresses of my 2 p4de.24xlarge compute nodes. We can take one of the IP addresses to describe the node as:

```bash
kubectl describe node ip-192-168-165-37.us-west-2.compute.internal
```
The above command describes a lot of detail of the node. To make sure EFA is installed correctly make sure you see the following:

```bash
Allocatable:
  cpu:                    95690m
  ephemeral-storage:      868645791124
  hugepages-1Gi:          0
  hugepages-2Mi:          21122Mi
  memory:                 1146004920Ki
  nvidia.com/gpu:         8
  pods:                   250
  vpc.amazonaws.com/efa:  4
```
For p4 nodes you will see ` vpc.amazonaws.com/efa:  4` and for p5.48xlarge nodes you should see ` vpc.amazonaws.com/efa:  32`.

```bash
NOTE: If EFA is enabled in the node group, edit the security group that the nodes are attached to and add a rule to allow all outgoing traffic originating from the same security group. This is required for EFA to work.

```

# 2. Mount Amazon FSx for Lustre file system on EKS

```bash
# From EC2 console
export MY_REGION=us-west-2
# FSX_SUBNET_ID should be same ID the compute nodes are present in. You can get this from the EKS console 
export FSX_SUBNET_ID=subnet-0edecd850cff2cfad
# From EC2 Auto Scaling Group
export EKS_INSTANCE_PROFILE_NAME=(eks-1ec6fc6b-1a19-d65d-66ac-293ff0a20eb9 )
export FSX_SECURITY_GROUP_NAME=eks-fsx-sg
export FSX_STORAGE_CLASS_NAME=fsx-sc
export FSX_POLICY_NAME=fsx-csi
# Get FSX_POLICY_DOC from https://github.com/aws-samples/aws-do-eks/blob/main/Container-Root/eks/deployment/csi/fsx/fsx-policy.json
export FSX_POLICY_DOC=file://fsx-policy.json

# Get VPC_ID from EKS console
export VPC_ID=vpc-04411d49af198a6ea

POLICY_ARN=$(aws iam create-policy --policy-name ${FSX_POLICY_NAME} --policy-document $FSX_POLICY_DOC --query "Policy.Arn" --output text)

INSTANCE_PROFILE=$(aws iam list-instance-profiles --query InstanceProfiles[?InstanceProfileName=="'${EKS_INSTANCE_PROFILE_NAME}'"].{InstanceProfileName:InstanceProfileName} --output text)

ROLE_NAME=$(aws iam get-instance-profile --instance-profile-name ${INSTANCE_PROFILE} --query InstanceProfile.Roles[0].RoleName --output text)

# Attach FSx Policy to role ${ROLE_NAME} ..."
aws iam attach-role-policy --policy-arn ${POLICY_ARN} --role-name ${ROLE_NAME}

export SECURITY_GROUP_ID=$(aws ec2 create-security-group --vpc-id ${VPC_ID} --region ${MY_REGION} --group-name ${FSX_SECURITY_GROUP_NAME} --description "FSx for Lustre Security Group" --query "GroupId" --output text)

export SUBNET_CIDR=$(aws ec2 describe-subnets --region ${MY_REGION} --query Subnets[?SubnetId=="'${FSX_SUBNET_ID}'"].{CIDR:CidrBlock} --output text)

aws ec2 authorize-security-group-ingress --region ${MY_REGION} --group-id ${SECURITY_GROUP_ID} --protocol tcp --port 988 --cidr ${SUBNET_CIDR}
```

```bash
echo "Installing FSx CSI driver ..."
kubectl apply -k "github.com/kubernetes-sigs/aws-fsx-csi-driver/deploy/kubernetes/overlays/stable/?ref=master"

# Storage Class
kubectl apply -f fsx-storage-class.yaml
kubectl get sc

root@cb9511473ccc:/eks/deployment/csi/fsx# kubectl get sc
NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
fsx-sc          fsx.csi.aws.com         Delete          Immediate              false                  22s
gp2 (default)   kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  12h
# To create the persistent volume we just need to apply this:



# Test
kubectl apply -f fsx-share-test.yaml

```

# 1. Execute in `aws-do-eks` container

```bash
cd aws-do-eks
./exec.sh
```

# 2. Pull Nemo Container

```bash
docker pull nvcr.io/nvidia/nemo:24.01.framework
```

# 3. Copy Launcher scripts

```bash
# Run Nemo container

cd /eks/deployment/distributed-training/pytorch/pytorchjob/nemo

docker cp -a <Nemo-Container-ID>:/opt/NeMo-Megatron-Launcher ./

```

# 4. Install Requirements

```bash
git clone https://github.com/aws-samples/awsome-distributed-training.git
cd ./awsome-distributed-training/3.test_cases/2.nemo-launcher/EKS/
pip install -r requirements.txt
```

# 5. Build and push AWS optimized Docker container

```bash
docker build -t ${REGISTRY}${IMAGE}${TAG} -f 0.Dockerfile .

echo "Logging in to $REGISTRY ..."
aws ecr get-login-password | docker login --username AWS --password-stdin $REGISTRY

# Create registry if it does not exist
REGISTRY_COUNT=$(aws ecr describe-repositories | grep ${IMAGE} | wc -l)
if [ "$REGISTRY_COUNT" == "0" ]; then
        echo ""
        echo "Creating repository ${IMAGE} ..."
        aws ecr create-repository --repository-name ${IMAGE}
fi

# Push image
echo ""

echo "Pushing image ${REGISTRY}${IMAGE}${TAG}"
docker image push ${REGISTRY}${IMAGE}${TAG}
```

# 6. Deploy kubeflow mpi-operator

You might need to restart mpi-operator

```bash
kubectl apply -f https://raw.githubusercontent.com/kubeflow/mpi-operator/v0.3.0/deploy/v2beta1/mpi-operator.yaml
kubectl apply -f ./clusterrole-mpi-operator.yaml

```

# 7. Put launcher scripts in /fsx-shared???

# 8. Run

```bash
python main.py

```
