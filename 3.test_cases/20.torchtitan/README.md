# Torchtitan Test Case  <!-- omit in toc -->

torchtitan is a proof-of-concept for Large-scale LLM training using native PyTorch. It is (and will continue to be) a repo to showcase PyTorch's latest distributed training features in a clean, minimal codebase. torchtitan is complementary to and not a replacement for any of the great large-scale LLM training codebases such as Megatron, Megablocks, LLM Foundry, Deepspeed, etc. Instead, we hope that the features showcased in torchtitan will be adopted by these codebases quickly. torchtitan is unlikely to ever grow a large community around it.

## 1. Preparation

This guide assumes that you have the following:

In case of Slurm based environment
* A functional Slurm cluster on AWS.
* Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
* An FSx for Lustre filesystem mounted on `/fsx`.

In case of Kubernetes environment

We recommend that you set up a Slurm cluster using the templates in the architectures [directory](../../1.architectures). You need to set the following environment variables to run this test case.
Modify the following snipet and prepare `.env` file. You can always load the variables with `source .env`:

```bash
cat > .env << EOF
export APPS_PATH=/fsx/apps
export ENROOT_IMAGE=$APPS_PATH/torchtitan.sqsh
export FSX_PATH=/fsx
export MODEL_PATH=$FSX_PATH/torchtitan
export TEST_CASE_PATH=${FSX_PATH}/awsome-distributed-training/3.test_cases/20.torchtitan
export HF_HOME=${FSX_PATH}/.cache
export WANDB_CONFIG_DIR=${FSX_PATH}
export WANDB_API_KEY=PUT_YOUR_API_KEY_HERE # You need to place your WANDB_API_KEY here 
EOF
```

On the head/login node of the cluster, clone the repository, move to the test case directory.

```bash
git clone https://github.com/aws-samples/awsome-distributed-training ${FSX_PATH}
cd ${TEST_CASE_PATH}
```


## 2. Build the container

Before running training jobs, you need to use a build docker container image. [Enroot](https://github.com/NVIDIA/enroot) will be used to turn the image into unprivileged sandbox for Slurm. 
You can build the image on your login node using the option 1 below, but build step may exceed the storage available on the head node so we reccomend building it on a compute node following instructions in option2.

### Option 1: Bulid image on login node

Below are the steps you need to follow:


1. Build the Docker image with the command below in this directory.

   ```bash
    docker build -t torchtitan -f 0.torchtitan.dockerfile .
   ```

## 3. Get access to the Llama3 model

Go to https://huggingface.co/meta-llama/Meta-Llama-3-70B and apply for the access
Go to https://huggingface.co/settings/tokens to create access token. 

In the login node, launch Python process on the head node, run the following:

```bash
    enroot start --env NVIDIA_VISIBLE_DEVICES=void \
        --mount ${FSX_PATH}:${FSX_PATH} ${ENROOT_IMAGE} \
        python -c "from huggingface_hub import login; login()"
```

It will prompt you to input the token. Paste the token and answer to `n` to the following question:

```bash
>> Add token as git credential? (Y/n) n
>> Token is valid (permission: read).
>> Your token has been saved to /home/ubuntu/.cache/huggingface/token
```

As you can see on the output, the access token stored under the
