## NeuronX Nemo Megatron on Slurm with Trn1

## 0. Prerequisites
```bash
aws ec2 create-key-pair --region us-west-2 --key-name lab-your-key --query KeyMaterial --output text > ~/.ssh/us-west-2.pem
chmod 400 ~/.ssh/us-west-2.pem
```

## 1. Bulid Custom Neuron AMI for ParallelCluster

```
packer build -only 'aws-pcluster-neuron.*' -var parallel_cluster_version=3.6.1 -var aws_region=us-west-2 -var "ami_version=1" packer-ami.pkr.hcl | tee aws-pcluster-neuron_ami.log
```

you will see 


```

==> Wait completed after 13 minutes 4 seconds

==> Builds finished. The artifacts of successful builds are:
--> aws-pcluster-neuron.amazon-ebs.aws-pcluster-ami: AMIs were created:
us-west-2: ami-0f5ed52f73351d999
```

## 3. Setup infrastrcutre

```
export REGION=us-west-2
export AZ=us-west-2d
VPC_NAME=vpc-neuronx-nemomegatron
aws cloudformation create-stack --stack-name ${VPC_NAME} \
    --template-body file://../1.architectures/1.vpc_network/2.vpc-one-az.yaml \
	--parameters ParameterKey=VPCName,ParameterValue=${VPC_NAME} ParameterKey=SubnetsAZ,ParameterValue=${AZ} \
	--region ${REGION} --capabilities=CAPABILITY_IAM
```



## 2. Launch ParallelCluster with AMI

create pcluster config
```
export REGION=us-west-2
export AZ=us-west-2d
export PLACEHOLDER_CUSTOM_AMI_ID=ami-0ef5eac7c4cd4b22e
export PLACEHOLDER_PUBLIC_SUBNET=subnet-0a910e572266c13bd
export PLACEHOLDER_PRIVATE_SUBNET=subnet-031418ea04ed99194
export PLACEHOLDER_SSH_KEY=dev-machine-us-west-2
export PLACEHOLDER_CAPACITY_RESERVATION_ID=cr-06d73238916b3c7a8
export PLACEHOLDER_PLACEMENT_GROUP=trn1-placement-group
export PLACEHOLDER_NUM_INSTANCES=32
cat ../../1.architectures/2.aws-parallelcluster/distributed-training-trn1_custom_ami.yaml | envsubst > pcluster.yaml 
```

```
pcluster create-cluster --cluster-configuration pcluster.yaml --cluster-name pcluster-neuronx-nemomegatron --region us-west-2
```


## 3. Connect to Cluster

```
pcluster ssh --dryrun true --cluster-name pcluster-neuronx-nemomegatron --region us-west-2 
```
{
  "command": "ssh ec2-user@xx.xx.xx.xx "
}


## X. Clean up

```
 pcluster delete-cluster  --cluster-name pcluster-neuronx-nemomegatron --region us-west-2      
```