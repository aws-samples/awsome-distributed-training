# Amazon Sagemaker HyperPod EKS Reference Architectures

## 1. Architectures

## 2. Prerequisits

## 3. Cluster setup



### Step1: Create VPC stack
```bash
export VPC_STACK_NAME=hyperpod-eks-vpc
export EKS_STACK_NAME=hyperpod-eks
export EKS_CLUSTER_NAME=hyperpod-cluster
export REGION=us-east-2
```

```bash
bin/deploy-cfn --region ${REGION}  --stack-name ${VPC_STACK_NAME} --template-file cfn/vpc.yaml
```

### Step2: Create EKS cluster

Retrieve Subnet IDs and Security Group ID:

```bash
SUBNET1=$(bin/cfn-output --region ${REGION} --stack-name ${VPC_STACK_NAME} --output-name PrivateSubnet1)
SUBNET2=$(bin/cfn-output --region ${REGION} --stack-name ${VPC_STACK_NAME} --output-name PrivateSubnet2)
SUBNET3=$(bin/cfn-output --region ${REGION} --stack-name ${VPC_STACK_NAME} --output-name PrivateSubnet3)
SECURITY_GROUP=$(bin/cfn-output --region ${REGION} --stack-name ${VPC_STACK_NAME} --output-name NoIngressSecurityGroup)
```

Then deploy an EKS  Stack as follows. This stack creates an EKS cluster and an EKS Cluster IAM Role while configuring the cluster with the VPC stack.

```bash
bin/deploy-cfn --region ${REGION} --stack-name ${EKS_STACK_NAME} --template-file cfn/eks.yaml \
    ParameterKey=ClusterName,ParameterValue=${EKS_CLUSTER_NAME} \
    ParameterKey=SecurityGroupId,ParameterValue=${SECURITY_GROUP} \
    ParameterKey=SubnetIds,ParameterValue=${SUBNET1}\\,${SUBNET2}\\,${SUBNET3} 
```

### Step3: Set up the EKS Cluster to be compatible with HyperPod

Now let's access to the cluster, 

```bash
aws --region ${REGION} eks update-kubeconfig --name ${EKS_CLUSTER_NAME}
```
Run `kubectl get nodes` and notice that no node is running on this cluster at this point:

```text
No resources found
```

```bash
kubectl apply -f manifests/hp-service-auth.yaml
```

```text
clusterrole.rbac.authorization.k8s.io/hyperpod-node-manager-role created
clusterrolebinding.rbac.authorization.k8s.io/hyperpod-nodes created
```

```bash
SERVICE_ROLE=$(bin/cfn-output --region ${REGION} --stack-name ${EKS_STACK_NAME} --output-name ServiceRole)
aws --region ${REGION} eks create-access-entry --cluster-name ${EKS_CLUSTER_NAME} \
    --principal-arn ${SERVICE_ROLE} --kubernetes-groups hyperpod-node-manager
```

```text
{
    "accessEntry": {
        "clusterName": "hyperpod-cluster",
        "principalArn": "arn:aws:iam::159553542841:role/hyperpod-eks-HyperPodServiceRoleAlternative",
        "kubernetesGroups": [
            "hyperpod-node-manager"
        ],
        "accessEntryArn": "arn:aws:eks:us-east-2:159553542841:access-entry/hyperpod-cluster/role/159553542841/hyperpod-eks-HyperPodServiceRoleAlternative/26c8a2fb-99f7-e415-050d-30a291bcbcd3",
        "createdAt": "2024-08-12T09:41:54.409000+00:00",
        "modifiedAt": "2024-08-12T09:41:54.409000+00:00",
        "tags": {},
        "username": "arn:aws:sts::159553542841:assumed-role/hyperpod-eks-HyperPodServiceRoleAlternative/{{SessionName}}",
        "type": "STANDARD"
    }
}
```


```
$ aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 590183648699.dkr.ecr.us-west-2.amazonaws.com
Login Succeeded




### Step3: Deploy HyperPod on the cluster

