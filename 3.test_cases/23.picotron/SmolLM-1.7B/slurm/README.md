## Running SmolLM-1.7B Training on Two Single-GPU EC2 Instances with Slurm

This guide demonstrates how to run distributed training across two GPU instances using Slurm. For simplicity and cost-effectiveness, we use instances with a single GPU each (e.g., g5.8xlarge) to showcase Tensor Parallelism (TP=2) training.

### Prerequisites

You will need:

* A Slurm cluster on AWS with at least two GPU compute nodes
* On each cluster node:
  * Docker
  * [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) for container orchestration
  * An FSx for Lustre filesystem mounted at `/fsx`
  * Shared home directory accessible across head and compute nodes

For cluster setup, we recommend using either AWS ParallelCluster or SageMaker HyperPod with our provided templates in the [architectures directory](../../../1.architectures).

* Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed on the cluster.
* An FSx for Lustre filesystem mounted on `/fsx`.
* A home directory that is shared across the head node and compute nodes.

We recommend setting up a Slurm cluster using either AWS ParallelCluster or SageMaker HyperPod with the templates provided in the architectures [directory](../../../1.architectures).

You need to build the `picotron` container image following the guidance in [here](..). Once you build the container, convert the Docker image to a squash file with the command below:

```bash
enroot import -o picotron.sqsh dockerd://picotron:latest
```

The rest of this guide assumes you have the following environment variables set:

```bash
# your Hugging Face token is needed to retrieve model and data from HF Hub
export HF_TOKEN="hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### How to run the distributed training job


First, run the following command to create configuration json file:

```bash
# TensorParallelism on 2 GPUs
docker run --rm -v ${PWD}:${PWD} picotron python3 create_config.py \
    --out_dir ${PWD}/conf --exp_name llama-1B-tp2 --dp 1 --tp 2 --pp 1  \
    --pp_engine 1f1b --model_name HuggingFaceTB/SmolLM-1.7B --num_hidden_layers 5 \
    --grad_acc_steps 2 --mbs 4 --seq_len 128 --hf_token ${HF_TOKEN}
```

It will create a config file `./conf/llama-1B-dp2-tp2-pp2/config.json` describing training configurations, including model architecuture, training configuration and data set to use. 

Now you are ready to submit the job:

```bash
sbatch train.sbatch
```


