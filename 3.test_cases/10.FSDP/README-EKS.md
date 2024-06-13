# Run Distributed Training of Llama 2 with PyTorch FSDP on Amazon EKS

These scripts provide an easy way to get started with multinode [FSDP](https://pytorch.org/tutorials/intermediate/FSDP_tutorial.html) training on EKS. It is designed to be as simple as possible, requires no data preparation, and uses a container image. 

## 0. Prerequisites

### 0.1. EKS Cluster
Before running this training, you'll need to create an Amazon EKS or a SageMaker HyperPod EKS cluster. Instructions can be found in [1.architectures](../../1.architectures), the [aws-do-eks](https://bit.ly/do-eks) project, or the [eks-blueprints](https://github.com/aws-ia/terraform-aws-eks-blueprints) project.

### 0.2. awsome-distributed-training source code
Clone this repo. 

```
git clone https://github.com/aws-samples/awsome-distributed-training/
cd awsome-distributed-training/3.test_cases/10.FSDP
```

### 0.3. Base image
The example requires building a container. We are going to use the [nccl-tests](github.com/aws-samples/awsome-distributed-training/micro-benchmarks/nccl-tests/nccl-tests.Dockerfile) container as base. The nccl-tests container is a prerequisite and can be built using the code below.

```bash
pushd ../../micro-benchmarks/nccl-tests
docker build -t nccl-tests:cuda12 -f nccl-tests.Dockerfile .
popd
```

### 0.4. Envsubst
If the [envsubst](https://github.com/a8m/envsubst) utility is not available in your environment, please install it, following the instructions appropriate for your operating system.

### 0.5. Kubeflow training operator
Deploy the Kubeflow training operator

```bash
kubectl apply -k "github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.7.0"
```

## 1. Build container image

Build a container image for this example using the code below:

```bash
export AWS_REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export REGISTRY=${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/
docker build -t ${REGISTRY}fsdp:pytorch2.2 .
```

## 2. Push container image to Amazon ECR

In this step we create a container registry if one does not exist, and push the container image to it.

```bash
# Create registry if needed
REGISTRY_COUNT=$(aws ecr describe-repositories | grep \"fsdp\" | wc -l)
if [ "$REGISTRY_COUNT" == "0" ]; then
        aws ecr create-repository --repository-name fsdp
fi

# Login to registry
echo "Logging in to $REGISTRY ..."
aws ecr get-login-password | docker login --username AWS --password-stdin $REGISTRY

# Push image to registry
docker image push ${REGISTRY}fsdp:pytorch2.2
```

## 3. Data

For this example, we'll be using the [C4 dataset](https://huggingface.co/datasets/allenai/c4), which is several hundred gigabytes. Instead of downloading the whole thing, the `create_streaming_dataloaders` function will stream the dataset from [HuggingFace](https://huggingface.co/datasets), so there's no data prep required for running this training. 

If you'd like to instead use your own dataset, you can do so by [formatting it as a HuggingFace dataset](https://huggingface.co/docs/datasets/create_dataset), and passing its location to the `--dataset_path` argument.

## 4. Launch training job

Generate the Kubernetes manifest and apply it to the cluster.

```bash
export IMAGE_URI=${REGISTRY}fsdp:pytorch2.2
export INSTANCE_TYPE=
export NUM_NODES=
export GPU_PER_NODE=
export EFA_PER_NODE=
export FI_PROVIDER=efa
cat fsdp.yaml-template | envsubst > fsdp.yaml

kubectl apply -f ./fsdp.yaml
```

EFA level variables are available for adjustment in fsdp.yaml-template
Keep FI_* values commented out for non-efa instances (G5, G4d, P3) or P5
Uncomment FI_* values for P4d instances

You can also adjust the training parameters in `TRAINING_ARGS` (for example, to train Llama 2 70b). Additional parameters can be found in `model/arguments.py`. Note that we use the same directory for both `--checkpoint_dir` and `--resume_from_checkpoint`. If there are multiple checkpoints, `--resume_from_checkpoint` will automatically select the most recent one. This way if our training is interupted for any reason, it will automatically pick up the most recent checkpoint.

## 5. Monitor training job

To see the status of your job, use the commands below

```bash
kubectl get pytorchjob 
kubectl get pods 
```

```log
NAME   STATE     AGE
fsdp   Running   5m

NAME                    READY   STATUS    RESTARTS        AGE
etcd-7787559c74-l9g92   1/1     Running   0               5m
fsdp-worker-0           1/1     Running   0               5m
fsdp-worker-1           1/1     Running   0               5m
fsdp-worker-2           1/1     Running   0               5m
fsdp-worker-3           1/1     Running   0               5m
fsdp-worker-4           1/1     Running   0               5m
fsdp-worker-5           1/1     Running   0               5m
fsdp-worker-6           1/1     Running   0               5m
fsdp-worker-7           1/1     Running   0               5m
```

Each of the pods produces job logs. One of the pods is elected master during job initialization. Only this pod will show the progress of the training job in its log. To find out which pod is currently the master, run the command below.

```bash
kubectl logs fsdp-worker-0 | grep master_addr=
```

```log
[2024-06-11 18:59:56,193] torch.distributed.elastic.agent.server.api: [INFO]   master_addr=fsdp-worker-1
```

This shows that the pod `fsdp-worker-1` is currently the master. To look at the current job logs, use the command below:

```bash
kubectl logs -f fsdp-worker-1
```

```log
...
2024-06-12 00:08:25 I [train.py:102] Batch 979 Loss: 5.63272, Speed: 0.43 samples/sec, lr: 0.000091
2024-06-12 00:08:44 I [train.py:102] Batch 980 Loss: 5.63327, Speed: 0.43 samples/sec, lr: 0.000091
2024-06-12 00:09:03 I [train.py:102] Batch 981 Loss: 5.95147, Speed: 0.43 samples/sec, lr: 0.000091
2024-06-12 00:09:21 I [train.py:102] Batch 982 Loss: 5.45894, Speed: 0.43 samples/sec, lr: 0.000091
```

## 6. Stop training job

To stop the current training job, use the following command.

```bash
kubectl delete -f ./fsdp.yaml
```

If you wish to launch a new job, you must first stop the previous one, even if it is in `Completed` state.

To modify training for a 13 or 70B Llama 2 model, just change the corresponding parameters based on the values in the [Llama 2 paper](https://arxiv.org/abs/2307.09288).

| Param                    |     7B      |     13B     |     70B     |
| ------------------------ | ----------- | ----------- | ----------- |
| intermediate_size        | 11008       | 13824       | 28672       |
| num_key_value_heads      | 32          | 40          | 8           |
| hidden_width             | 4096        | 5120        | 8192        |
| num_layers               | 32          | 40          | 80          |
| num_heads                | 32          | 40          | 64          |

