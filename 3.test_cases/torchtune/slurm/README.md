# End-to-End LLM Model Development with Torchtune on Slurm <!-- omit in toc -->

This test case illustrates the setup and execution of each step in LLMOps on Slurm using the Torchtune environment. This README provides a detailed guide for configuring the necessary environment. For hands-on LLMOps examples, refer to the [tutorials](./tutorials) section.

## 1. Prerequisites

Before proceeding with each step of this test case, ensure you have the following prerequisites:

* A Slurm cluster configured as specified
* Access tokens and keys for Hugging Face and Weights & Biases (W&B)

Further setup details are provided below.

### Slurm Cluster

For this guide, you should have:

* An operational Slurm cluster on AWS.
* Docker, [Pyxis](https://github.com/NVIDIA/pyxis), and [Enroot](https://github.com/NVIDIA/enroot) installed.
* An FSx for Lustre filesystem mounted at `/fsx`.

It's recommended to establish your Slurm cluster using the templates found in the [architectures directory](../../../1.architectures).

### Token and Access Key

To access Meta-Llama-3-70B, visit [Meta-Llama-3-70B](https://huggingface.co/meta-llama/Meta-Llama-3-70B) and request access. Subsequently, create an access token at [Hugging Face Tokens](https://huggingface.co/settings/tokens) (`HF_TOKEN`).

For monitoring model training and computational resource usage, [Weights & Biases](https://wandb.ai/) will be utilized. Create an account and retrieve your `WANDB_API_KEY` from the Weights & Biases [Settings](https://wandb.ai/settings). For comprehensive setup instructions, consult the Weights & Biases [Quickstart Guide](https://docs.wandb.ai/quickstart).

## 2. Preparation

This section illustartes how to fetch all the necessary code bases and set up development environment.

### Clone repository

On the head/login node of the cluster, clone the repository, move to the test case directory.

```bash
cd /fsx/${USER}
git clone https://github.com/aws-samples/awsome-distributed-training ${FSX_PATH}/${USER}/awsome-distributed-training
cd /fsx/${USER}/awsome-distributed-training/3.test_cases/torchtune/slurm
```

Then clone `torchtune`:

```bash
git clone https://github.com/pytorch/torchtune.git torchtune
```

The remaining contents use `USER=ubuntu` for the sake of illustration.

### Configure environment variables

Run `configure-env-vars.sh` to create `.env` file. This file will be sourced by all the subsequent job files:

```bash
bash configure-env-vars.sh
```

The script will prompt you to input `WANDB_API_KEY` and `HF_KEY`:

```bash
Setting up environment variables
Please enter your WANDB_API_KEY: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Please enter your HF_KEY: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
.env file created successfully
Please run the following command to set the environment variables
source .env
```

The following environment variable will be on `.env` file. Feel free to modify `configure-env-vars.sh` to customize.

```bash
cat .env
```

```bash
export FSX_PATH=/fsx/ubuntu
export APPS_PATH=/fsx/ubuntu/apps
export ENROOT_IMAGE=/fsx/ubuntu/apps/torchtune.sqsh
export MODEL_PATH=/fsx/ubuntu/models/torchtune
export TEST_CASE_PATH=/fsx/ubuntu/awsome-distributed-training/3.test_cases/torchtune/slurm
export HF_HOME=/fsx/ubuntu/.cache/huggingface
export WANDB_CACHE_DIR=/fsx/ubuntu/.cache/wandb
export WANDB_DIR=/fsx/ubuntu/models/torchtune/wandb
export WANDB_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## 3. Build the container

Before running training jobs, you need to use a build docker container image. [Enroot](https://github.com/NVIDIA/enroot) will be used to turn the image into unprivileged sandbox for Slurm.  

Submit `build-image.sbatch`:

```bash
sbatch build-image.sbatch
```

You can check build progress through log files:

```bash
tail -f logs/build-image_*
```

The build process was successuful if you could see the following lines at the end of the log:

```bash
Number of fifo nodes 0
Number of socket nodes 0
Number of directories 41628
Number of ids (unique uids + gids) 1
Number of uids 1
        root (0)
Number of gids 1
        root (0)

==> logs/build-image_xxx.out <==
Image built and saved as /fsx/ubuntu/apps/torchtune.sqsh
```

## 4. Next steps

Now that you are ready to move on to actual experiments. Go to `tutorials` directory for respective examples.

