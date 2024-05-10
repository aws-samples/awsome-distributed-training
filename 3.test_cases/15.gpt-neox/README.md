# GPT-NeoX Test Cases <!-- omit in toc -->

GPT-NeoX is an [EleutherAI](https://www.eleuther.ai)'s library for training large-scale language models on GPUs. This framework is based on [NVIDIA's Megatron Language Model](https://github.com/NVIDIA/Megatron-LM) and has been augmented with techniques from [DeepSpeed](https://www.deepspeed.ai) as well as some novel optimizations. 

## 1. Preparation

This guide assumes that you have the following:

* A functional Slurm cluster on AWS.
* Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
* An FSx for Lustre filesystem mounted on `/fsx`.

We recommend that you set up a Slurm cluster using the templates in the architectures [directory](../../1.architectures). You need to set the following environment variables to run this test case:

```bash
export APPS_PATH=/fsx/apps
export ENROOT_IMAGE=$APPS_PATH/gpt-neox.sqsh
export FSX_PATH=/fsx
export DATA_PATH=$FSX_PATH/pile_subset     # use pile to download entire dataset (see 4. Data preparation)
export MODEL_PATH=$FSX_PATH/gpt-neox
export TEST_CASE_PATH=${HOME}/15.gpt-neox  # where you copy the test case or set to your test case path
cd $TEST_CASE_PATH                         # Note that we assume that you are here during the following command executions
```



## 2. Build the container

Before running training jobs, you need to use a build docker container image. [Enroot](https://github.com/NVIDIA/enroot) will be used to turn the image into unprivileged sandbox for Slurm. 
You can build the image on your login node using the option 1 below, but build step could overwhelm it as it will compile [flash-attention](https://github.com/Dao-AILab/flash-attention).
If you want to avoid that, follow steps in option 2.

### Option 1: Bulid image on login node

Below are the steps you need to follow:


1. Build the Docker image with the command below in this directory.

   ```bash
    docker build -t gpt-neox -f 0.gpt-neox.dockerfile .
   ```

If you wish to reduce memory footprint of the build process, consider tweaknig `MAX_JOBS` for `flash-attn` compile (in `0.gpt-neox.dockerfile` line 172).

2. Once the Docker image is built, you can check if it is present with `docker images`. You should see an output similar to this one:

   ```bash
    REPOSITORY   TAG       IMAGE ID       CREATED          SIZE
    gpt-neox     latest    b6c49033c424   9 minutes ago    24.7GB
   ...
   ```

3. Convert the Docker image to a squash file with the command below.

   ```bash
   enroot import -o ${ENROOT_IMAGE} dockerd://gpt-neox:latest
   ```

   The file will be stored in the `/apps` directory (default). The output should look as below.

    ```bash
    [INFO] Fetching image

    36a8c752c28a2db543d2a632a3fc1fcbd5789a6f3d45b9d3a24632420dedcfa8

    [INFO] Extracting image content...
    [INFO] Creating squashfs filesystem...

    Parallel mksquashfs: Using 32 processors
    Creating 4.0 filesystem on /apps/gpt-neox.sqsh, block size 131072.
    [========================================================================================================================================================================================================================-] 291068/291068 100%

    Exportable Squashfs 4.0 filesystem, gzip compressed, data block size 131072
            uncompressed data, uncompressed metadata, uncompressed fragments, uncompressed xattrs
            duplicates are not removed
    ...
    ```

Once done proceed to the next stage.

### Option 2: Build image on a compute node

In this option, you will use a compute node to build the image. Submit the job as:

    ```bash
    sbatch 1.build-image.sbatch
    ```

