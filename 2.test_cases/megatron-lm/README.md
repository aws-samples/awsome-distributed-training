# MegatronLM Test Case

[MegatronLM](https://github.com/NVIDIA/Megatron-LM) is a framework from Nvidia that can be used to train LLMs. We recommend that you read papers on the framework to know the different knobs you can tune and in particular these articles:

- [Megatron-LM: Training Multi-Billion Parameter Language Models Using Model Parallelism](https://arxiv.org/abs/1909.08053)
- [Efficient Large-Scale Language Model Training on GPU Clusters Using Megatron-LM](https://arxiv.org/abs/1909.08053)

To run a test case you will go through a series of steps described below:

1. Build the data preprocessing container.
2. Preprocess the data using a tokenizer and the preprocessing container.
3. Build the container for distributed training
4. Train!

We describe the steps below for Slurm users. EKS users may follow the sequence but details will vary.

## 0. Preparation

This guide assumes that you have the following:

- A functional Slurm cluster on AWS.
- Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
- An FSx for Lustre filesystem mounted on `/fsx`.

You will also setup the following variables in your terminal environment.

```bash
export DATA_PATH=/fsx
export APPS_PATH=/apps
```

## 1. Data Preprocessing

Before running training jobs you need to retrieve input data and preprocess it. This section of the guide you will retrieve a container then you convert it into a Squash file via [Enroot](https://github.com/NVIDIA/enroot), you will then retrieve input data ans tokenize it using the GPT2 vocabulary.

Below are the steps you need to follow:

1. Copy the file `0.data-preprocessing.Dockerfile` or its content to your head-node.
2. Build the container image with the command below

   ```bash
   docker build -t megatron-preprocess -f 0.data-preprocessing.Dockerfile .
   ```

3. Once the image is built, you can check if it is present with `docker images`. You should see an output similar to this one:
   ```
   [ec2-user@ip-10-0-10-78 ~]$ docker images
   REPOSITORY               TAG         IMAGE ID       CREATED          SIZE
   megatron-preprocess           latest      a33c9d5bcb6e   9 seconds ago    20.7GB
   <none>                   <none>      36b0f224fb00   25 minutes ago   20.5GB
   nvcr.io/nvidia/pytorch   23.01-py3   9eda6061497d   5 months ago     20.5GB
   ```
4. Create the squash file with the command below.
   ```bash
   enroot import -o /apps/megatron-preprocess.sqsh  dockerd://megatron-preprocess:latest
   ```
   The file will be stored in the `/apps` directory. The output should look as below.

    ```bash
    [ec2-user@ip-10-0-10-78 ~]$ enroot import -o ./megatron-preprocess.sqsh  dockerd://megatron-preprocess:latest
    [INFO] Fetching image

    e19aa13505c1710876982dc440226dc479da5177dc4770452cc79bedc8b5b41d

    [INFO] Extracting image content...
    [INFO] Creating squashfs filesystem...

    Parallel mksquashfs: Using 32 processors
    Creating 4.0 filesystem on /home/ec2-user/megatron-preprocess.sqsh, block size 131072.
    [==========================================================/] 299550/299550 100%

    Exportable Squashfs 4.0 filesystem, gzip compressed, data block size 131072
       uncompressed data, uncompressed metadata, uncompressed fragments, uncompressed xattrs
       duplicates are not removed
    ...
    ```

5. Run the code below to retrieve the input datasets and vocabulary.

    ```bash
    #!/bin/bash
    mkdir -p cd ${DATA_PATH}/gpt2
    cd ${DATA_PATH}/gpt2

    wget https://huggingface.co/bigscience/misc-test-data/resolve/main/stas/oscar-1GB.jsonl.xz
    wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-vocab.json
    wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-merges.txt
    xz -d oscar-1GB.jsonl.xz
    ```

6. Now you copy the file `1.data-preprocessing.sbatch` or its content on your cluster then submit a preprocessing jobs with the command below:

    ```bash
    sbatch 1.data-preprocessing.sbatch
    ```

7. You will see a new file in your current working directory called `slurm-XY.out` where `XY` is a number. This is your outputfile and will capture the `STDOUT` and `STDERR` from your job. You can check how it progresses via the command `tail -f slurm-XY.out` but with the relevant filename. The file content will be similar to the below:

    ```
    0: Opening /fsx/oscar-1GB.jsonl
    0: Time to startup: 0.9956498146057129
    0: Processed 1000 documents (101.28050670002645 docs/s, 1.258563987556778 MB/s).
    0: Processed 2000 documents (188.07992853480727 docs/s, 2.3571624257619614 MB/s).
    ...
    0: Processed 78000 documents (1293.9967304914383 docs/s, 16.67556064420713 MB/s).
    0: Processed 79000 documents (1298.6715286585202 docs/s, 16.763634765830606 MB/s).
    ```

Voilà! You have executed the preprocessing job. You will go through the steps to run your training job.


## 2. Distributed training

Now that the data is preprocessed, we will pretrain a GPT3 model MegatronLM.


1. Copy the file `2.training-batch.Dockerfile` or its content to your cluster.
2. Build the container with the command below. This will build a container with all the required dependencies to train your models with MegatronLM.
    ```bash
    docker build -t megatron-training ./training.Dockerfile .
    ```
3. Convert the docker container to a squash file in `/apps`.
    ```bash
    enroot import -o /apps/megatron-training.sqsh  dockerd://megatron-training:latest
    ```
4. You copy the file `3.distributed-training.sbatch`  on your cluster then submit a training jobs with the command below:

    ```bash
    sbatch 3.distributed-training.sbatch
    ```
5. You copy the file `3.distributed-training.sbatch`  on your cluster then submit a training jobs with the command below:

    ```bash
    sbatch 3.distributed-training.sbatch
    ```
6. The training starts running and should and output as below if successful.
