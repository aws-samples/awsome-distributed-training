# Run Nemo on EKS

# 0. Prerequisites
1. Have a EFA enabled Kubernetes cluster with 2 `p4de.24xlarge` nodes
2. `k get pods -A` looks like

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

3. Mount FSX file system

```bash
# From EC2 console
export MY_REGION=us-west-2
export FSX_SUBNET_ID=subnet-0edecd850cff2cfad
# From EC2 Auto Scaling Group
export EKS_INSTANCE_PROFILE_NAMES=(eks-1ec6fc6b-1a19-d65d-66ac-293ff0a20eb9 )
export FSX_SECURITY_GROUP_NAME=eks-fsx-sg
export FSX_STORAGE_CLASS_NAME=fsx-sc
export FSX_POLICY_NAME=fsx-csi
export FSX_POLICY_DOC=file://fsx-policy.json
export VPC_ID=vpc-04411d49af198a6ea

POLICY_ARN=$(aws iam create-policy --policy-name ${FSX_POLICY_NAME} --policy-document $FSX_POLICY_DOC --query "Policy.Arn" --output text)

ROLE_NAME=$(aws iam get-instance-profile --instance-profile-name ${INSTANCE_PROFILE} --query InstanceProfile.Roles[0].RoleName --output text)

INSTANCE_PROFILE=$(aws iam list-instance-profiles --query InstanceProfiles[?InstanceProfileName=="'${EKS_INSTANCE_PROFILE_NAMES[0]}'"].{InstanceProfileName:InstanceProfileName} --output text)


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

