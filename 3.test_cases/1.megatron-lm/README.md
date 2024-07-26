# MegatronLM Test Case

[MegatronLM](https://github.com/NVIDIA/Megatron-LM) is a framework from Nvidia that can be used to train LLMs. We recommend that you read papers on the framework to know the different knobs you can tune and in particular these articles:

- [Megatron-LM: Training Multi-Billion Parameter Language Models Using Model Parallelism](https://arxiv.org/abs/1909.08053)
- [Efficient Large-Scale Language Model Training on GPU Clusters Using Megatron-LM](https://arxiv.org/abs/1909.08053)

To run a test case you will go through a series of steps described below:

1. Prepare your environment
2. Build a container, download, and pre-process the data
3. Train!

We describe the steps below for Slurm and Kubernetes users.

## 1. Preparation

This guide assumes that you have the following:

- A functional Slurm or EKS cluster on AWS.
- Docker, for Slurm [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) need to be installed as well.
- An FSx for Lustre filesystem mounted on `/fsx` in all Slurm nodes or a persistent volume claim that can be mounted on `/fsx` in pods running on EKS. An example of setting up FSx on EKS is available [here](https://github.com/aws-samples/aws-do-eks/tree/main/Container-Root/eks/deployment/csi/fsx). 

It is recommended that you use the templates in the architectures [directory](../../1.architectures) for Parallel Cluster

You will also setup the following variables in your terminal environment.

```bash
export DATA_PATH=/fsx # FSx for Lustre shared file-system
```

Make sure that your current directory is under a shared filesystem such as `/fsx/` or the home directory when using [Parallel Cluster](../../1.architectures/aws-parallelcluster).

## 2. Data Preprocessing

Before running training jobs you need to retrieve input data and preprocess it. This section of the guide you will retrieve a container then you convert it into a Squash file via [Enroot](https://github.com/NVIDIA/enroot), you will then retrieve input data ans tokenize it using the GPT2 vocabulary.

Below are the steps you need to follow:

1. Copy the file `0.distributed-training.Dockerfile` or its content to your head-node or any instance where you have the [Docker](https://docs.docker.com/get-docker/) cli available.
2. Build the container image with the command below

   ```bash
   docker build -t megatron-training -f 0.distributed-training.Dockerfile .
   ```

3. Once the image is built, you can check if it is present with `docker images`. You should see an output similar to this one:

   ```text
   [ec2-user@ip-10-0-10-78 ~]$ docker images
   REPOSITORY               TAG         IMAGE ID       CREATED          SIZE
   megatron-training           latest      a33c9d5bcb6e   9 seconds ago    20.7GB
   ```

4. Prepare the image for your target environment.

   If you are using SLURM - create the squash file with the command below.
 
   ```bash
   enroot import -o megatron-training.sqsh  dockerd://megatron-training:latest
   ```

   The file will be stored in the current directory (if left as default). The output should look as below.

    ```bash
    [ec2-user@ip-10-0-10-78 ~]$ enroot import -o ./megatron-training.sqsh  dockerd://megatron-training:latest
    [INFO] Fetching image

    e19aa13505c1710876982dc440226dc479da5177dc4770452cc79bedc8b5b41d

    [INFO] Extracting image content...
    [INFO] Creating squashfs filesystem...

    Parallel mksquashfs: Using 32 processors
    Creating 4.0 filesystem on /home/ec2-user/megatron-training.sqsh, block size 131072.
    [==========================================================/] 299550/299550 100%

    Exportable Squashfs 4.0 filesystem, gzip compressed, data block size 131072
       uncompressed data, uncompressed metadata, uncompressed fragments, uncompressed xattrs
       duplicates are not removed
    ...
    ```
    
   If you are using EKS, tag and push the image to your container registry.
   
   ```bash
   # Tag image
   export AWS_REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
   export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
   export REGISTRY=${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/
   docker tag megatron-training:latest ${REGISTRY}megatron-training:latest
   # Create repository if needed
   REGISTRY_COUNT=$(aws ecr describe-repositories | grep \"megatron-training\" | wc -l)
   if [ "$REGISTRY_COUNT" == "0" ]; then
      aws ecr create-repository --repository-name megatron-training
   fi
   # Login to registry
   echo "Logging in to $REGISTRY ..."
   aws ecr get-login-password | docker login --username AWS --password-stdin $REGISTRY
   # Push image to registry
   docker image push ${REGISTRY}megatron-training:latest
   ```

5. Run the code below to retrieve the input datasets and vocabulary.
    
   SLURM: 
   
    ```bash
    #!/bin/bash
    mkdir -p gpt2
    cd gpt2/

    wget https://huggingface.co/bigscience/misc-test-data/resolve/main/stas/oscar-1GB.jsonl.xz
    wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-vocab.json
    wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-merges.txt
    xz -d oscar-1GB.jsonl.xz
    ```

   EKS:
   
   Run the following snippet to crete a job container that mounts the fsx volume
   and downloads the data on it.
   
   ```bash
   cat getdata-job.yaml-template | envsubst > getdata-job.yaml
   kubectl apply -f ./getdata-job.yaml
   ```
   
   Monitor the job progress
   
   ```bash
   kubectl logs -f $(kubectl get pods | grep getdata | cut -d ' ' -f 1)
   ```
   
   When status is `Completed`, delete the job pod:
   
   ```bash
   kubectl delete -f ./getdata-job.yaml
   ```

6. Preprocess the data

   SLURM:
   
   Copy the file `1.data-preprocessing.sbatch` or its content on your SLURM cluster then submit a preprocessing jobs with the command below:

    ```bash
    sbatch 1.data-preprocessing.sbatch
    ```

   You will see a new file in your current working directory called `slurm-XY.out` where `XY` is a number.
   This is your output file and will capture the `STDOUT` and `STDERR` from your job.
   You can check how it progresses via the command `tail -f slurm-XY.out` but with the relevant filename.
   The file content will be similar to the below:

    ```text
    0: Opening /fsx/oscar-1GB.jsonl
    0: Time to startup: 0.9956498146057129
    0: Processed 1000 documents (101.28050670002645 docs/s, 1.258563987556778 MB/s).
    0: Processed 2000 documents (188.07992853480727 docs/s, 2.3571624257619614 MB/s).
    ...
    0: Processed 78000 documents (1293.9967304914383 docs/s, 16.67556064420713 MB/s).
    0: Processed 79000 documents (1298.6715286585202 docs/s, 16.763634765830606 MB/s).
    ```
    
   EKS:
    
   Launch a job pod that preprocesses the data.
    
    ```bash
    export DATA_PATH=/fsx/gpt2
    cat prepdata-job.yaml-template | envsubst > prepdata-job.yaml
    kubectl apply -f ./prepdata-job.yaml
    ```
    
   Monitor the job progress.
    
    ```bash
    kubectl logs -f $(kubectl get pods | grep prepdata | cut -d ' ' -f 1)
    ```
    
   When the job status is `Completed`, clean up the job pod.
    
    ```bash
    kubectl delete -f ./prepdata-job.yaml
    ```

   Voilà! You have executed the preprocessing job. Next, you will go through the steps to run your training job.

## 3. Distributed training

Now that the data is preprocessed, we will pretrain a GPT3 model MegatronLM.

   SLURM:
   
   Copy the file `2.distributed-training.sbatch` to your cluster then submit a training jobs with the command below:


   ```bash
   sbatch 2.distributed-training.sbatch
   ```

   The training starts running and should produce an output similar to below if successful.

   ```text
   1:  iteration       25/73242187 | consumed samples:           50 | elapsed time per iteration (ms): 87.0 | learning rate: 1.638E-08 | global batch size:     2 | lm loss: 1.086954E+01 | loss scale: 4294967296.0 | grad norm: 0.000 | number of skipped iterations:   0 | number of nan iterations:   0 |
   1:  iteration       26/73242187 | consumed samples:           52 | elapsed time per iteration (ms): 86.5 | learning rate: 1.704E-08 | global batch size:     2 | lm loss: 1.086217E+01 | loss scale: 4294967296.0 | grad norm: 0.000 | number of skipped iterations:   0 | number of nan iterations:   0 |
   1:  iteration       27/73242187 | consumed samples:           54 | elapsed time per iteration (ms): 88.4 | learning rate: 1.769E-08 | global batch size:     2 | lm loss: 1.087129E+01 | loss scale: 4294967296.0 | grad norm: 0.000 | number of skipped iterations:   0 | number of nan iterations:   0 |
   ```


   EKS:

   Launch a PyTorchJob
    
    
   ```bash
   export DATA_PATH=/fsx
   export NUM_NODES=1
   export INSTANCE_TYPE=p5.48xlarge
   export IMAGE_URI=${REGISTRY}megatron-training:latest
   export GPU_PER_NODE=8
   export EFA_PER_NODE=32
   export TENSOR_PARALLEL=8
   export PIPELINE_PARALLEL=1
   export NUM_LAYERS=36
   export HIDDEN_SIZE=4096
   export NUM_ATTENTION_HEADS=32
   export SEQ_LENGTH=2048
   export MAX_POSITION_EMBEDDINGS=2048
   export MICRO_BATCH_SIZE=1
   export GLOBAL_BATCH_SIZE=288
   cat pytorchjob.yaml-template | envsubst > pytorchjob.yaml
   kubectl apply -f ./pytorchjob.yaml
   ```

   The training starts running:
    
   ```bash
   kubectl get pods
   ```
    
   You should see one etcd and one worker pod.
    
   ```text
   NAME                    READY   STATUS      RESTARTS   AGE
   etcd-7787559c74-wpcb9   1/1     Running     0          3m10s
   megatron-worker-0       1/1     Running     0          3m10s
   ```
    
   Log lines describing the iterations show that the training is working properly.
    
   ```bash
   kubectl logs -f megatron-worker-0
   ```
   
   An abbreviated sample log is shown below:
    
   ```text
   ...
   using torch.float16 for parameters ...
   ------------------------ arguments ------------------------
   accumulate_allreduce_grads_in_fp32 .............. False
   adam_beta1 ...................................... 0.9
   adam_beta2 ...................................... 0.95
   ...
   -------------------- end of arguments ---------------------
   setting number of micro-batches to constant 288
   > building GPT2BPETokenizer tokenizer ...
   > padded vocab (size: 50257) with 943 dummy tokens (new size: 51200)
   > initializing torch distributed ...
   > initialized tensor model parallel with size 8
   > initialized pipeline model parallel with size 1
   > setting random seeds to 1234 ...
   > compiling dataset index builder ...
   make: Entering directory '/workspace/Megatron-LM/megatron/core/datasets'
   ...
   time to initialize megatron (seconds): 15.424
   [after megatron is initialized] datetime: 2024-07-16 22:14:01
   building GPT model ...
   > number of parameters on (tensor, pipeline) model parallel rank (4, 0): 941594624
   ...
   > building train, validation, and test datasets ...
   > datasets target sizes (minimum size):
       train:      146484375
       validation: 5863680
       test:       11520
   ...
   iteration        1/  508626 | consumed samples:          288 | elapsed time per iteration (ms): 255940.5 | learning rate: 0.000E+00 | global batch size:   288 | loss scale: 4294967296.0 | number of skipped iterations:   1 | number of nan iterations:   0 |
   iteration        2/  508626 | consumed samples:          576 | elapsed time per iteration (ms): 243438.3 | learning rate: 0.000E+00 | global batch size:   288 | loss scale: 2147483648.0 | number of skipped iterations:   1 | number of nan iterations:   0 |
   iteration        3/  508626 | consumed samples:          864 | elapsed time per iteration (ms): 243344.4 | learning rate: 0.000E+00 | global batch size:   288 | loss scale: 1073741824.0 | number of skipped iterations:   1 | number of nan iterations:   0 |
   ...
   ```
    
   You can stop the training job by executing:
    
   ```bash
   kubectl delete -f ./pytorchjob.yaml
   ```
    
## 4. What's next?

The example is based on the GPT3 example from MegatronLM's [repository](https://github.com/NVIDIA/Megatron-LM/blob/main/examples/pretrain_gpt.sh). You can modify `NUM_ATTENTION_HEADS`, `NUM_LAYERS`, and `HIDDEN_SIZE`  based on the Table 1 (Page 8) of the document [Efficient Large-Scale Language Model Training on GPU Clusters Using Megatron-LM](https://arxiv.org/abs/2104.04473) to change the model size. You can also run the following commands to launch training for different model sizes before submitting a job as follows: `NUM_LAYERS=64 HIDDEN_SIZE=8192 NUM_ATTENTION_HEADS=48 sbatch  3.distributed-training.sbatch`

| Model size | Parameters                                                |
|------------|-----------------------------------------------------------|
| 1.7B       | `NUM_ATTENTION_HEADS=24 HIDDEN_SIZE=2304 NUM_LAYERS=24`   |
| 3.6B       | `NUM_ATTENTION_HEADS=32 HIDDEN_SIZE=3072 NUM_LAYERS=30`   |
| 7.5B       | `NUM_ATTENTION_HEADS=32 HIDDEN_SIZE=4096 NUM_LAYERS=36`   |
| 18.4B      | `NUM_ATTENTION_HEADS=48 HIDDEN_SIZE=6144 NUM_LAYERS=40`   |
| 39.1B      | `NUM_ATTENTION_HEADS=64 HIDDEN_SIZE=8192 NUM_LAYERS=48`   |
| 76.1B      | `NUM_ATTENTION_HEADS=80 HIDDEN_SIZE=10240 NUM_LAYERS=60`  |
| 145.6B     | `NUM_ATTENTION_HEADS=96 HIDDEN_SIZE=12288 NUM_LAYERS=80`  |
| 310.1B     | `NUM_ATTENTION_HEADS=128 HIDDEN_SIZE=16384 NUM_LAYERS=96` |


Following the same pattern, you can train other models. Pretraining scripts for models like 
Bert, ICT, and T5 are already included in the Megatron-LM container under `/workspace/Megatron-LM`. 

## 5. Appendix: Llama2 on Slurm

To pretrain Llama2, you must visit <https://huggingface.co/meta-llama/Llama-2-7b-hf> to download the tokenizers files (i.e., `tokenizer.json` and `tokenizer.model`). Registration required. Alternatively, you may train your own tokenizer but this is beyond the scope for this document. Either way, once you have the tokenizer files, you need to upload them to the FSx Lustre that your Slurm cluster mounts.

The remaining steps are similar to the GPT3 example. For more information, please refer to the official Megatron-LM documentation on Llama2 [here](https://github.com/NVIDIA/Megatron-LM/blob/main/docs/llama2.md).

### 5.1. Download and prepocess data

```bash
mkdir -p llama2
# Then, place `tokenizer.json` and `tokenizer.model` to this `llama2/` directory.

# Download sample dataset
wget -P llama2 https://huggingface.co/bigscience/misc-test-data/resolve/main/stas/oscar-1GB.jsonl.xz
xz -d llama2/oscar-1GB.jsonl.xz

sbatch 3.data-preproc-llama2.sbatch
```

### 5.2. Run pretraining job

Edit `4.pre-train-llama2.sbatch` to choose the model size you want to train. Do this by commenting and uncommenting the related stanzas. Feel free to experiment with the hyperparameters such as parallelism, batches, etc. (for more details, please refer to the [Megatron-LM project](https://github.com/NVIDIA/Megatron-LM/) and the Megatron papers ([Shoeybi20](https://arxiv.org/abs/1909.08053), [Narayanan21](https://arxiv.org/abs/2104.04473)).

```bash
sbatch 4.pre-train-llama2.sbatch
```

Tips: the Llama2 example prints the estimated FLOPS/GPU (enabled via `--log-throughput` in the pretrain `.sbatch` file). You might want to look at [PR-682](https://github.com/NVIDIA/Megatron-LM/pull/682) and decide whether to patch your Megatron-LM to adjust the way FLOPS/GPU is calculated.
