# Running Slurm on HyperPod EKS with Slinky

### What is the Slinky Project? 
---

### Architecture

---

### Release Notes 

The following was tested on 4 `g5.8xlarge` instances (1 A10G Tensor Core GPU each) for hosting the Worker Pod NodeSet. 2 `m5.2xlarge` instances were also allocated for separately hosting the Controller Pod and Login Pod. Other components (Accounting, MariaDB, RestAPI, Token Creation, Exporter) were also colocated across the 2 `m5.2xlarge` instances for simplicity, but you may wish to deploy them on separate instance depending on your specific needs. This can be accomplished by modifying the associated node affinity configurations, which is discussed in more detail below. 

Testing used [Slurm Operator v0.2.1](https://github.com/slinkyproject/slurm-operator/pkgs/container/slurm-operator) (pulled from the Slinky GHCR) and [Slurm Cluster v0.3.0](https://github.com/SlinkyProject/slurm-operator/tree/main/helm/slurm) (packaged and deployed locally using the main Slinky repo branch) in order to include the NoteSet volume mount and Login Pod features. These features are expected to be included in the official Slurm Cluster v0.3.0 release when it becomes available on the Slinky GHCR repo, along with a new version of the Slurm Operator with corresponding validating webhooks.

Note that the [Slinky Project](https://github.com/SlinkyProject) is under active development and could introduce breaking changes that may require modified deployment steps and configuration changes. 

Worker pods were built with Python 3.12.8 + PyTorch 2.6.0 + CUDA 12.6 + NCCL 2.23.4 pre-installed in the container image. See [Docker Build for the Slurmd Deep Learning Container](./Docker-Build-README.md) for details. 
 
* * *


### Set Up the HyperPod Cluster: 

Follow the [Prerequisites](https://catalog.workshops.aws/sagemaker-hyperpod-eks/en-US/00-setup)and [Cluster Configuration](https://catalog.workshops.aws/sagemaker-hyperpod-eks/en-US/01-cluster) steps of the [HyperPod EKS Workshop](https://catalog.workshops.aws/sagemaker-hyperpod-eks/en-US). 

Be sure to modify the Accelerated and General Purpose instance groups as needed to deploy the desired instance type and number of nodes. 

Add an access entry (if needed):

```
export AWS_ACCOUNT_ID=<your-account-id-here>

export EKS_CLUSTER_NAME=sagemaker-hyperpod-eks-cluster

export ROLE_ARN=arn:aws:iam::$AWS_ACCOUNT_ID:role/Administrator

export PLCY_ARN=arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy

export AWS_REGION=us-west-2

aws eks create-access-entry \
 --cluster-name $EKS_CLUSTER_NAME \
 --principal-arn $ROLE_ARN \
 --type STANDARD \
 --region $AWS_REGION
 
aws eks associate-access-policy \
 --cluster-name $EKS_CLUSTER_NAME \
 --principal-arn $ROLE_ARN \
 --policy-arn $PLCY_ARN \
 --access-scope type=cluster \
 --region $AWS_REGION
 
```

Update your kubectl context: 

```

aws eks update-kubeconfig --name $EKS_CLUSTER_NAME

kubectl get nodes

```

* * *

### Create an FSx for Lustre Storage Class: 

Follow the [Setup FSx for Lustre File System](https://catalog.workshops.aws/sagemaker-hyperpod-eks/en-US/01-cluster/06-fsx-for-lustre) of the [HyperPod EKS Workshop](https://catalog.workshops.aws/sagemaker-hyperpod-eks/en-US). 

Verify` fsx-sc` Storage Class: 

```
kubectl get storageclass fsx-sc -oyaml
```

* * *

### Create an FSx for OpenZFS Storage Class: 

Install the[OpenZFS CSI driver](https://github.com/kubernetes-sigs/aws-fsx-openzfs-csi-driver/blob/main/docs/install.md). Set up permissions using IAM roles for service accounts, and taint the nodes as recommended:

```

eksctl create iamserviceaccount \
    --name fsx-openzfs-csi-controller-sa \
    --namespace kube-system \
    --cluster $EKS_CLUSTER_NAME \
    --attach-policy-arn arn:aws:iam::aws:policy/AmazonFSxFullAccess \
    --approve \
    --role-name AmazonEKSFSxOpenZFSCSIDriverFullAccess \
    --region $AWS_REGION
  
kubectl taint nodes --all fsx.openzfs.csi.aws.com/agent-not-ready:NoExecute

helm repo add aws-fsx-openzfs-csi-driver \
    https://kubernetes-sigs.github.io/aws-fsx-openzfs-csi-driver
 
helm repo update

helm upgrade --install aws-fsx-openzfs-csi-driver \
    --namespace kube-system \
    --set controller.serviceAccount.create=false \
    aws-fsx-openzfs-csi-driver/aws-fsx-openzfs-csi-driver
    
kubectl get pods -n kube-system \
 -l app.kubernetes.io/part-of=aws-fsx-openzfs-csi-driver
 
```

Follow the [Dynamic Provisioning](https://github.com/kubernetes-sigs/aws-fsx-openzfs-csi-driver/tree/main/examples/kubernetes/dynamic-provisioning) guide to create an FSx for OpenZFS Storage Class: 

```

export PRIVATE_SUBNET_ID=<your-subnet-id-here>
export SECURITY_GROUP_ID=<your-security-group-id-here> 

kubectl apply -f openzfs-storageclass.yaml

kubectl get sc openzfs-sc -oyaml

```

* * *

### Install the AWS Load Balancer Controller:

Following [these instructions](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html): 

```
export EKS_CLUSTER_NAME=sagemaker-hyperpod-eks-cluster
export VPC_ID=<your-vpc-id-here>
export AWS_REGION=us-west-2
export AWS_ACCOUNT_ID=<your-account-id-here>

# manually update crds
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.12.0/docs/install/iam_policy.json

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy-v2.12.0 \
    --policy-document file://iam_policy.json
    
eksctl create iamserviceaccount \
    --cluster=$EKS_CLUSTER_NAME \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy-v2.12.0 \
    --override-existing-serviceaccounts \
    --region $AWS_REGION \
    --approve
    
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$EKS_CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$AWS_REGION \
  --set vpcId=$VPC_ID
  
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

kubectl get sa aws-load-balancer-controller -n kube-system -oyaml

```

* * *

### Instill Prerequisites (Cert Manager and Prometheus):  

Follow the [QuickStart Guide](http://curl%20-l%20https//raw.githubusercontent.com/SlinkyProject/slurm-operator/refs/tags/v0.1.0/helm/slurm-operator/values.yaml%20/%20%20%20-o%20values-operator.yaml%20helm%20install%20slurm-operator%20oci://ghcr.io/slinkyproject/charts/slurm-operator%20/%20%20%20--values=values-operator.yaml%20--version=0.1.0%20--namespace=slinky%20--create-namespace) to install Cert Manager and Prometheus as [Pre-Requisites](https://github.com/SlinkyProject/slurm-operator/blob/main/docs/quickstart.md#pre-requisites).

Verify Pre-Requisites Instillation: 

```
 kubectl get all -n cert-manager
 kubectl get all -n prometheus
```

* * *

### Install the Slurm Operator: 

For [Slurm Operator](https://github.com/SlinkyProject/slurm-operator/blob/main/docs/quickstart.md#pre-requisites) Installation,  we'll install release v0.2.1, which is the latest release available at the time of testing.

 Note: We will locally build and deploy a pre-release v0.3.0 of the [Slurm Cluster](https://github.com/SlinkyProject/slurm-operator/tree/main/helm/slurm) from the main branch of the Slinky Project repository. The project is being actively developed, so there is a risk of pulling down breaking changes, but it includes the features to [add additional volume mounts to compute NodeSets](https://github.com/SlinkyProject/slurm-operator/commit/b0e111b0a8434e38b5fb37a2051e7525d5679319) and [deploy Login Pods](https://github.com/SlinkyProject/slurm-operator/commit/37f020f041556164b9c935f799b51df65d22aefe). 

```

curl -L https://raw.githubusercontent.com/SlinkyProject/slurm-operator/refs/tags/v0.2.1/helm/slurm-operator/values.yaml \
  -o values-operator-0.2.1.yaml
  
# Delete any stale crds (if you deployed an older version)
kubectl delete crd clusters.slinky.slurm.net
kubectl delete crd nodesets.slinky.slurm.net
  
helm install slurm-operator oci://ghcr.io/slinkyproject/charts/slurm-operator \
  --values=values-operator-0.2.1.yaml --version=0.2.1 --namespace=slinky --create-namespace

```

Verify Slurm Operator Instillation:

```
kubectl get all -n slinky
```

* * *

### Install the Slurm Cluster:

To deploy the **slurm cluster**, we first need to make some modifications to the [values.yaml](https://github.com/SlinkyProject/slurm-operator/blob/dd65faba359702a8eda6cce9484b702f2fd2ae2e/helm/slurm/values.yaml)` file.  After that, again, in order to test the latest changes in release **v0.3.0**, we’ll locally package and deploy the helm chart from the main branch of the cloned repo. For your convenience, we've provided a copy of the [values.yaml](./values.yaml) file with most of the configuration changes mentioned below already implemented. 

Clone the Slurm Operator repository, which also contains the Helm chart artifacts for the Slurm Cluster: 
```
git clone https://github.com/SlinkyProject/slurm-operator.git

```
(Optional) If you wish to start from scratch, open the [values.yaml](https://github.com/SlinkyProject/slurm-operator/blob/dd65faba359702a8eda6cce9484b702f2fd2ae2e/helm/slurm/values.yaml)` file associated with the Slurm Cluster Helm Chart: 
```
code slurm-operator/helm/slurm/values.yaml

```
Otherwise, you can use the [values.yaml](./values.yaml) file we've provided. 

Verify the existence of the instance type label for controller affinity: 

```
export GEN_INSTANCE_TYPE=ml.m5.2xlarge

kubectl get nodes -l node.kubernetes.io/instance-type=$GEN_INSTANCE_TYPE

```

#### Controller Modifications: 

Configure controller affinity: 

```
controller: 
...
  affinity: 
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: "node.kubernetes.io/instance-type"
                operator: "In"
                values:
                  - "ml.m5.2xlarge"
...
```

#### Compute NodeSet Modifications:

Verify the existence of the instance type label for compute node selector:

```
ACCEL_INSTANCE_TYPE=ml.g5.8xlarge
 
 kubectl get nodes -l node.kubernetes.io/instance-type=$ACCEL_INSTANCE_TYPE
 
```

Change the compute node name, replica count, and node selector:: 

```
compute:
...
    nodeSets:
        - name: hp-node
          ...
          replicas: 4
          ...
          nodeSelector:
            kubernetes.io/os: linux
            node.kubernetes.io/instance-type: ml.g5.8xlarge
...
```

Create the slurm namespace: 

```
kubectl create ns slurm
```

Create a FSx for Lustre Persistent Volume Claim (PVC) in the slurm namespace:

This is needed to reference for node volume mounts later. 

```
kubectl apply -f lustre-pvc-slurm.yaml
```

Verify FSx for Lustre PVC creation:

```
kubectl get pvc -n slurm

# check for a bound state 
kubectl get pvc fsx-claim  -n slurm -ojson \
 | jq -r .status.phase

# get the the volume ID
kubectl get pv $(kubectl get pvc fsx-claim  -n slurm -ojson \
 | jq -r .spec.volumeName) -ojson \
 | jq -r .spec.csi.volumeHandle
 
```

Create an FSx for OpenZFS PVC in the slurm namespace:

```
kubectl apply -f openzfs-pvc-slurm.yaml

```

Verify FSx for OpenZFS PVC creation: 

```
kubectl get pvc -n slurm

# check for a bound state 
kubectl get pvc openzfs-claim  -n slurm -ojson \
 | jq -r .status.phase

# get the volume ID
kubectl get pv $(kubectl get pvc openzfs-claim -n slurm -ojson \
 | jq -r .spec.volumeName) -ojson \
 | jq -r .spec.csi.volumeHandle
 
```

Add the  FSx for Lustre and OpenZFS PVCs to the list of compute node volumes:

```
compute:
    nodesets:
        - name: hp-node
        ...
        volumes: 
            - name: fsx-lustre
              mountPath: /fsx
              persistentVolumeClaim: 
                claimName: fsx-claim
            - name: fsx-openzfs
              mountPath: /home
              persistentVolumeClaim:
                claimName: openzfs-claim
        ...
```

Configure resources for compute nodes:
Note: limits are required, otherwise the compute nodes will not deploy. 

```
compute: 
    nodesets: 
        - name: hp-node
        ...
        resources:
            limit: 
                cpu: "32"
                memory: "128Gi"
                nvidia.com/gpu: "1"
            requests:
                cpu: "1"
                memory: "1Gi"
                nvidia.com/gpu: "1"
        ...
```

Modify the compute node container image to use the [Slurmd Deep Learning Container](./Docker-Build-README.md) (Slurmd DLC) build:

```
compute: 
    nodesets:
        - name: compute-node
        ...      
          # Set the image to use.
          image:
            #
            # -- (string)
            # Set the image repository to use.
            repository: "<your-account-id-here>.dkr.ecr.us-west-2.amazonaws.com/dlc-slurmd"
            #
            # -- (string)
            # Set the image tag to use.
            tag: "24.11.4-ubuntu24.04"
        ...
```
For your convenience, we've pre-build a Slurmd DLC for and made it available in an ECR public repository, but you can use the provided [dlc-slurmd.Dockerfile](./dlc-slurmd.Dockerfile) to modify and build your own.  

#### Login Node Modifications: 

Add the  FSx for Lustre and OpenZFS PVCs to the list of login node volumes:

```
login:
   ...
   volumes: 
       - name: fsx-lustre
            mountPath: /fsx
            persistentVolumeClaim: 
              claimName: fsx-claim

        - name: fsx-openzfs
            mountPath: /home
            persistentVolumeClaim:
              claimName: openzfs-claim
   ...
```

Generate an SSH key for root authorization: 

```

export EMAIL_ADDR=<your-email-here>

ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_slurm -C "${EMAIL_ADDR}"

cat ~/.ssh/id_ed25519_slurm.pub

# ssh-ed25519 <public-key-content> janedoe@example.com

```

Specify the root SSH authorized key in `values.yaml`:

```
login: 
    ...
    rootSshAuthorizedKeys:
        - "ssh-ed25519 <public-key-content> janedoe@example.com"
    ...
```

Disable SSSD:  the `nsswitchConf` (Name Service Switch configuration) file tells Linux how to resolve different types of system information like users, groups, passwords, etc. By setting everything to just `files` we're telling the system to only use local files for authentication and not to try SSSD or other sources. This is simpler and more reliable when you just want to use SSH key authentication for root access, as the SSH keys are stored in local files anyway (/root/.ssh/authorized_keys).

```
...
login:     
  ...  
  nsswitchConf:
    passwd: files
    group: files
    shadow: files
    gshadow: files
    sudoers: files
    hosts: files
    networks: files
    protocols: files
    services: files
    ethers: files
    rpc: files
    netgroup: files
    automount: files
  ...
...      
```

Define the content of the sshd_config file:

```
...
login:
  sshdConfig:
    # This is the actual content of the sshd_config file
    AcceptEnv: "LANG LC_*"
    AuthorizedKeysFile: "/root/.ssh/authorized_keys"
    ChallengeResponseAuthentication: "no"
    ClientAliveCountMax: "3"
    ClientAliveInterval: "60"
    LogLevel: "INFO"
    PasswordAuthentication: "no"
    PermitRootLogin: "yes"
    Port: "22"
    PrintMotd: "no"
    Protocol: "2"
    PubkeyAuthentication: "yes"
    Subsystem: "sftp internal-sftp"
    TCPKeepAlive: "yes"
    UseDNS: "no"
    UsePAM: "no"
    X11Forwarding: "no"
...    
```

Update the **slurm-login** service port:

```
login:
  ...
  servicePort: 22
  ...
```

#### Deploy the Slurm Cluster 

Locally package and deploy the **slurm cluster** using the modified `values.yaml` file:

```
helm dependency update slurm-operator/helm/slurm

helm package slurm-operator/helm/slurm

slurm-0.3.0.tgz

# Dry run 
helm install --dry-run slurm slurm-0.3.0.tgz \
--values=values.yaml \
--namespace=slurm 

helm install slurm slurm-0.3.0.tgz \
--values=values.yaml \
--namespace=slurm

```

Note: Release v0.2.1 of the slurm-operator validating webhook may throw a few warning about not recognizing `spec.template.spec.volumes[].mountPath` fields. This is not surprising given we are using the newer pre-release v0.3.0 of the slurm cluster, but it doesn’t appear to cause any functional errors. 


Watch the deployment status of the Slurm cluster:

```
kubectl --namespace=slurm get pods -l app.kubernetes.io/instance=slurm --watch
```

Verify deployment status of all components:

```
kubectl get all -n slurm
```

#### Configure Network Load Balancer provisioning using the AWS Load Balancer Controller

Manually add annotation to the slurm-login service:

```
export PUBLIC_SUBNET_ID_1=<your-public-subnet-1-here>
export PUBLIC_SUBNET_ID_2=<your-public-subnet-2-here>

kubectl annotate service slurm-login -n slurm \
  service.beta.kubernetes.io/aws-load-balancer-type="nlb" \
  service.beta.kubernetes.io/aws-load-balancer-scheme="internet-facing" \
  service.beta.kubernetes.io/aws-load-balancer-nlb-target-type="ip" \
  service.beta.kubernetes.io/aws-load-balancer-subnets="$PUBLIC_SUBNET_ID_1,$PUBLIC_SUBNET_ID_2" \
  service.beta.kubernetes.io/aws-load-balancer-healthcheck-port="22" \
  --overwrite
  
kubectl describe service slurm-login -n slurm

```

Any annotations added to the slurm cluster `values.yaml` file for the slurm-login service are currently ignored, but AWS Load Balancer Controller actively watches for and implements annotation changes.  It Automatically adds inbound rules to the node security group to allow traffic from the NLB security group on the target port (22 in this case). 
* * *

### Basic Tests:

SSH into the login node as root from the NLB endpoint: 

```

SLURM_LOGIN_HOSTNAME="$(kubectl get services -n slurm -l app.kubernetes.io/instance=slurm,app.kubernetes.io/name=login -o jsonpath="{.items[0].status.loadBalancer.ingress[0].hostname}")"
ssh -i ~/.ssh/id_ed25519_slurm -p 22 root@$SLURM_LOGIN_HOSTNAME

```

Check the available nodes: 

```

sinfo 

PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
hp-node      up   infinite      4   idle hp-node-[0-3]
all*         up   infinite      4   idle hp-node-[0-3]

```

Verify  FSx for Lustre and OpenZFS filesystem mounts on the login pod: 

```

df -h 

Filesystem                                             Size  Used Avail Use% Mounted on
overlay                                                500G   30G  471G   6% /
tmpfs                                                   64M     0   64M   0% /dev
tmpfs                                                   63G     0   63G   0% /sys/fs/cgroup
10.1.12.93@tcp:/7c5dpb4v                               1.2T  7.8M  1.2T   1% /fsx
fs-03221b7c7d3767607.fsx.us-west-2.amazonaws.com:/fsx   64G     0   64G   0% /home
tmpfs                                                  115G  4.0K  115G   1% /etc/slurm
/dev/nvme0n1p1                                         100G   23G   78G  23% /run
/dev/nvme1n1                                           500G   30G  471G   6% /etc/hostname
shm                                                     64M     0   64M   0% /dev/shm
tmpfs                                                  115G  4.0K  115G   1% /etc/sssd/sssd.conf
tmpfs                                                  115G   12K  115G   1% /etc/ssh/ssh_host_rsa_key
tmpfs                                                   63G     0   63G   0% /proc/acpi
tmpfs                                                   63G     0   63G   0% /sys/firmware

exit

```

Verify  FSx for Lustre and OpenZFS filesystem mounts on the worker node pods: 

```

kubectl -n slurm exec -it pod/slurm-compute-hp-node-0 -- bash --login

df -h

Filesystem                                             Size  Used Avail Use% Mounted on
overlay                                                500G   31G  470G   7% /
tmpfs                                                   64M     0   64M   0% /dev
tmpfs                                                   63G     0   63G   0% /sys/fs/cgroup
10.1.12.93@tcp:/7c5dpb4v                               1.2T  7.5M  1.2T   1% /fsx
fs-03221b7c7d3767607.fsx.us-west-2.amazonaws.com:/fsx   64G     0   64G   0% /home
tmpfs                                                  115G  4.0K  115G   1% /etc/slurm
/dev/nvme0n1p1                                         100G   23G   78G  23% /run
/dev/nvme1n1                                           500G   31G  470G   7% /etc/hostname
shm                                                     64M     0   64M   0% /dev/shm
tmpfs                                                  115G     0  115G   0% /var/log/slurm

```

Check the installed CUDA compiler version on worker node pods:

```

nvcc --version

# nccl-slurmd
nvcc: NVIDIA (R) Cuda compiler driver
Copyright (c) 2005-2023 NVIDIA Corporation
Built on Tue_Aug_15_22:02:13_PDT_2023
Cuda compilation tools, release 12.2, V12.2.140
Build cuda_12.2.r12.2/compiler.33191640_0

# dlc-slurmd
nvcc: NVIDIA (R) Cuda compiler driver
Copyright (c) 2005-2024 NVIDIA Corporation
Built on Tue_Oct_29_23:50:19_PDT_2024
Cuda compilation tools, release 12.6, V12.6.85
Build cuda_12.6.r12.6/compiler.35059454_0

```

Check the NCCL version on worker node pods:

```
ldconfig -v | grep "libnccl.so" | tail -n1 | sed -r 's/^.*\.so\.//'

2.23.4
```

Confirm NCCL headers are installed worker node pods:

```
find /usr/local/lib/ -name "nccl.h" 2>/dev/null

/usr/local/lib/python3.12/site-packages/torch/include/torch/csrc/cuda/nccl.h

exit
```

* * *

### FSDP Test 

SSH into the login pod as root, clone the repo, and create a checkpoints directory: 

```

SLURM_LOGIN_HOSTNAME="$(kubectl get services -n slurm -l app.kubernetes.io/instance=slurm,app.kubernetes.io/name=login -o jsonpath="{.items[0].status.loadBalancer.ingress[0].hostname}")"
ssh -i ~/.ssh/id_ed25519_slurm -p 22 root@$SLURM_LOGIN_HOSTNAME

# install git 
apt update
apt install -y git 
git --version 

# install vim
`apt install ``-``y vim `
vim --version

cd /fsx
git clone https://github.com/aws-samples/awsome-distributed-training/
cd awsome-distributed-training/3.test_cases/pytorch/FSDP/slurm

mkdir checkpoints
```

Download the c4 dataset to avoid throttling errors from HuggingFace:

```
mkdir -p /fsx/datasets/c4

apt install -y python3.12-venv
python3 -m venv env
source env/bin/activate
pip install --upgrade pip
pip install datasets

python3 download_c4.py

deactivate
```

Kick-off training:

```
sbatch llama2_7b-training.sbatch
```

Watch the output logs from login pod:

```

tail -f logs/llama2_7b-FSDP_$(squeue -h -u $USER -o "%i" | head -1).out

```

Watch the error logs from `slurm-compute-hp-node-0`:

```
# from a new terminal window 
kubectl -n slurm exec -it pod/slurm-compute-hp-node-0 -- bash --login

cd /fsx/awsome-distributed-training/3.test_cases/pytorch/FSDP/slurm

watch "grep 'Batch.*Loss' logs/llama2_7b-FSDP_65.err"

tail -f logs/llama2_7b-FSDP_$(squeue -h -u $USER -o "%i" | head -1).err | grep --line-buffered 'Batch.*Loss'

```

Watch squeue from `slurm-compute-hp-node-1`:

```
# from a new terminal window 
kubectl -n slurm exec -it pod/slurm-compute-hp-node-1 -- bash --login

# 1 second updates
watch -n 1 squeue

```

Watch checkpoints from `slurm-compute-hp-node-2`:

```
# from a new terminal window
kubectl -n slurm exec -it pod/slurm-compute-hp-node-2 -- bash --login

cd /fsx/awsome-distributed-training/3.test_cases/pytorch/FSDP/slurm

# highlight changes, show timestamps, 5 second updates
watch -n 5 -d "ls -lh checkpoints"

```

* * *

### Clean Up:

```

rm -rf checkpoints/*

rm -rf logs/*

kubectl delete pvc fsx-lustre-pvc -n slurm

helm uninstall slurm -n slurm 
helm uninstall slurm-operator -n slinky

helm uninstall prometheus -n prometheus
helm uninstall cert-manager -n cert-manager

kubectl delete pvc fsx-claim -n slurm
kubectl delete pvc openzfs-claim

helm uninstall aws-fsx-csi-driver -n kube-system
helm uninstall aws-fsx-openzfs-csi-driver -n kube-system

eksctl delete iamserviceaccount \
  --name fsx-csi-controller-sa \
  --namespace kube-system \
  --cluster $EKS_CLUSTER_NAME
  
eksctl delete iamserviceaccount \
  --name fsx-openzfs-csi-controller-sa \
  --namespace kube-system \
  --cluster $EKS_CLUSTER_NAME

```
