# Llama3 Test Case  <!-- omit in toc -->

Llama3 is...

## 1. Preparation

This guide assumes that you have the following:

* A functional Slurm cluster on AWS.
* Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
* An FSx for Lustre filesystem mounted on `/fsx`.

We recommend that you set up a Slurm cluster using the templates in the architectures [directory](../../1.architectures). You need to set the following environment variables to run this test case:

```bash
export APPS_PATH=/fsx/apps
export ENROOT_IMAGE=$APPS_PATH/llama3.sqsh
export FSX_PATH=/fsx
export MODEL_PATH=$FSX_PATH/llama3
export TEST_CASE_PATH=${HOME}/18.llama3   # where you copy the test case or set to your test case path
cd $TEST_CASE_PATH                         # Note that we assume that you are here during the following command executions
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

## 3. Chat with llama3

In this step, you will use Slurm interactive job functionality. 