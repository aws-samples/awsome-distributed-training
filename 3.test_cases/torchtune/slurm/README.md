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

Create an access token at [Hugging Face Tokens](https://huggingface.co/settings/tokens) (`HF_TOKEN`).

For monitoring model training and computational resource usage, [Weights & Biases](https://wandb.ai/) will be utilized. Create an account and retrieve your `WANDB_API_KEY` from the Weights & Biases [Settings](https://wandb.ai/settings). For comprehensive setup instructions, consult the Weights & Biases [Quickstart Guide](https://docs.wandb.ai/quickstart).

## 2. Preparing the Environment

This section outlines the steps to acquire the necessary codebases and configure your development environment.

### Cloning Repositories

Start by cloning the required repository on the cluster's head/login node, then navigate to the specific test case directory:

```bash
cd /fsx/${USER}
git clone https://github.com/aws-samples/awsome-distributed-training /fsx/${USER}/awsome-distributed-training
cd /fsx/${USER}/awsome-distributed-training/3.test_cases/torchtune/slurm
```

For demonstration purposes, we will proceed with `USER=ubuntu`.

Following that, clone the torchtune repository:

```bash
git clone https://github.com/pytorch/torchtune.git torchtune
```

### Setting Up Environment Variables

Initiate the configuration of your environment by executing the `configure-env-vars.sh` script. This action generates a `.env` file, which is crucial for defining the environment variables needed by all subsequent job files:

```bash
bash configure-env-vars.sh
```

During this setup, you'll be prompted to provide your `WANDB_API_KEY` and `HF_KEY`. These keys are essential for integrating with the Weights & Biases and Hugging Face platforms, respectively:

```bash
Setting up environment variables
Please enter your WANDB_API_KEY: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Please enter your HF_KEY: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
.env file created successfully
Please run the following command to set the environment variables
source .env
```

The `.env` file will include the following predefined variables. You have the flexibility to modify the `configure-env-vars.sh` script to better suit your project's specific needs:

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

## 3. Building the Torchtune Container

Before initiating any training jobs, it's essential to prepare a Docker container image. We'll utilize [Enroot](https://github.com/NVIDIA/enroot), a tool designed to convert Docker images into unprivileged sandboxes. This is particularly useful for running containers within Slurm-managed clusters.

### Submitting the Build Job

To start the build process, submit the `build-image.sbatch` script to Slurm:

```bash
sbatch build-image.sbatch
```

#### Monitoring the Build Progress

Keep an eye on the build progress by tailing the log files:

```bash
tail -f logs/build-image_*
```

A successful build process is indicated by the following lines at the end of the log file:

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
These lines confirm that the image has been successfully built and is now stored at the specified location, ready for use.

## 4. Proceeding to Experiments

With the torchtune container now built and ready, you're all set to dive into the actual experiments. Navigate to the [tutorials](./tutorials) directory to explore various examples.




