# Llama3 Test Case  <!-- omit in toc -->

Llama3 is...

## 1. Preparation

This guide assumes that you have the following:

* A functional Slurm cluster on AWS.
* Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
* An FSx for Lustre filesystem mounted on `/fsx`.

We recommend that you set up a Slurm cluster using the templates in the architectures [directory](../../1.architectures). You need to set the following environment variables to run this test case.
Modify the following snipet and prepare `.env` file. You can always load the variables with `source .env`:

```bash
cat > .env << EOF
export APPS_PATH=/fsx/apps
export ENROOT_IMAGE=$APPS_PATH/llama3.sqsh
export FSX_PATH=/fsx
export MODEL_PATH=$FSX_PATH/llama3
export TEST_CASE_PATH=${FSX_PATH}/awsome-distributed-training/3.test_cases/19.llama-recipes
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

Clone two llama sample repositories

```bash
git clone https://github.com/meta-llama/llama3.git
git clone https://github.com/meta-llama/llama-recipes.git
```

## 2. Build the container

Before running training jobs, you need to use a build docker container image. [Enroot](https://github.com/NVIDIA/enroot) will be used to turn the image into unprivileged sandbox for Slurm. 
You can build the image on your login node using the option 1 below, but build step may exceed the storage available on the head node so we reccomend building it on a compute node following instructions in option2.

### Option 1: Bulid image on login node

Below are the steps you need to follow:


1. Build the Docker image with the command below in this directory.

   ```bash
    docker build -t llama3 -f 0.llama3.dockerfile .
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


## 4. Finetune Llama3 model

In this step, you will fine tune llama model, using Alpaca dataset

This example making use of W&B experiment tracking. 
by using use_wandb flag as below. You can change the project name, entity and other wandb.init arguments in wandb_config.


## 5. Chat with Finetuned model

In this step, you will use Slurm interactive job functionality to communicate with llama3 model.



## 6. Evaluate model

