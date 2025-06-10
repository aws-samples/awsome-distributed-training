# Pre-train LLMs with PyTorch FSDP Slurm clusters

In this section, we will walk you through how to pre-train variants of Llama 2, Llama 3.1, Llama 3.2 and Mistral models with PyTorch FSDP using the [C4 dataset](https://huggingface.co/datasets/allenai/c4).

## PyTorch FSDP
PyTorch FSDP (Fully Sharded Data Parallel) is an advanced distributed training approach in PyTorch that enables efficient training of large models across multiple GPUs or nodes.
#### Key Features:

- **Parameter Sharding**: Unlike traditional DistributedDataParallel (DDP) which replicates the full model on each GPU, FSDP shards model parameters, gradients, and optimizer states across all participating devices
- **Memory Efficiency**: Significantly reduces memory footprint per GPU, making it possible to train models that would otherwise be too large
- **Communication Optimization**: Reduces communication overhead by only gathering parameters when needed for computation


Visit the [documentation](https://docs.pytorch.org/docs/stable/fsdp.html) to learn more about PyTorch FSDP.

## Prerequisites

Cluster Setup

- You will need a Slurm cluster in your AWS account with NVIDIA GPU compute nodes (see table below for guidance). We recommend using either AWS ParallelCluster or SageMaker HyperPod. Please follow this [guide](https://catalog.workshops.aws/sagemaker-hyperpod/en-US/01-cluster) to deploy a SageMaker HyperPod cluster.

As guidance, below are the minimum requirements to pre-train the various models across various GPU platforms:

| Model | Minimum Platform Without OOM |
|-------|----------------------------|
| Llama 3.1 8B | 1× g6e.12xlarge |
| Llama 3.2 1B | 2× g5.8xlarge |
| Llama 3.2 3B | 1× g5.12xlarge, 1× g6e.12xlarge |
| Llama 2 13B | 2× g6e.12xlarge |
| Llama 2 70B | 2× p5en.48xlarge, 4 × p5.48xlarge |
| Llama 3.1 70B | 4× p5en.48xlarge, 4 × p5.48xlarge |

- An FSx for Lustre filesystem mounted on /fsx in all Slurm nodes


## Create a Python Virtual Environment

On your cluster head node,
1. Navigate to your shared FSx for Lustre file system.
* If you followed the tutorial linked above to deploy your cluster, it will be location at `/fsx`.
2. Clone this repo.

```bash
cd /fsx
git clone https://github.com/aws-samples/awsome-distributed-training/
cd awsome-distributed-training/3.test_cases/pytorch/FSDP
```

3. Create a Python Virtual Environment to install the necessary packages. Run the `create_venv.sh` script.

```bash
bash create_venv.sh
source env/bin/activate
```

* By creating this environment on the shared FSx for Lustre volume, all compute nodes in our cluster will have access to it.


## Dataset 

For this example, you'll be using the [C4 dataset](https://huggingface.co/datasets/allenai/c4), which is several hundred gigabytes. Instead of downloading the entire dataset at once, the `create_streaming_dataloaders` function will stream the dataset from [HuggingFace](https://huggingface.co/datasets), so there's no data prep required for running this training.

If you'd like to instead use your own dataset, you can do so by [formatting it as a HuggingFace dataset](https://huggingface.co/docs/datasets/create_dataset), and passing its location to the `--dataset_path` argument.

## Models
This sample provides model configuration files to enable you to pre-train  Llama 2 (7B, 13B, 70B), Llama 3.1 (8B, 70B), Llama 3.2 (1B, 3B), Mistral 8x7B and Mistral Mathstral models. The configuration files are located in the `src/models` directory with details on the model's intermediate_size, num_key_value_heads, hidden_width, num_layers and num_heads.

#### Llama Model Architecture Parameters

| Parameter            | Llama 2 7B | Llama 2 13B | Llama 2 70B | Llama 3.1 8B | Llama 3.1 70B | Llama 3.2 1B | Llama 3.2 3B |
|----------------------|------------|-------------|-------------|--------------|---------------|--------------|--------------|
| intermediate_size    | 11008      | 13824       | 28672       | 14336        | 28672         | 8192         | 11008        |
| num_key_value_heads  | 32         | 40          | 8           | 8            | 8             | 8            | 8            |
| hidden_width         | 4096       | 5120        | 8192        | 4096         | 8192          | 2048         | 3072         |
| num_layers           | 32         | 40          | 80          | 32           | 80            | 16           | 28           |
| num_heads            | 32         | 40          | 64          | 32           | 64            | 32           | 24           |
| max_context_length   | 4096       | 4096        | 4096        | 128K         | 128K          | 128K         | 128K         |

## Launch Training
### Slurm batch script configurations

We also provide the corresponding Slurm batch script for each of the models to launch your training. These are located in the `slurm` directory.

1. You need to adjust the number of training nodes by modifying `#SBATCH --nodes=4` to match the number of nodes you would like to launch the training on.
2. You also need to adjust `GPUS_PER_NODE` to match the number of GPUs on your instance type following the GPU instance guide  below:

| Instance Type | GPUS_PER_NODE |
|--------------|---------------|
| g5.8xlarge, g6e.8xlarge | 1 |
| g5.12xlarge, g6e.12xlarge, g5.24xlarge, g6e.24xlarge | 4 |
| g5.48xlarge, g6e.48xlarge | 8 |
| p4d.24xlarge, p4de.24xlarge | 8 |
| p5.48xlarge, p5e.48xlarge, p5en.48xlarge | 8 |
| p6-b200.48xlarge | 8 |

3. If you are using non-EFA enabled instances, such as G4dn, or single GPU g5/g6e nodes, comment out all EFA environment variables on lines 36-42. Refer to the [EFA cheat sheet](https://github.com/aws-samples/awsome-distributed-training/blob/main/1.architectures/efa-cheatsheet.md) to learn more about the EFA environment variables.

4. You can also adjust the training parameters in `TRAINING_ARGS` (for example, to increase batch size). Additional parameters can be found in `src/model_utils/arguments.py`. Note that we use the same directory for both `--checkpoint_dir` and `--resume_from_checkpoint`. If there are multiple checkpoints, `--resume_from_checkpoint` will automatically select the most recent one. This way if our training is interrupted for any reason, it will automatically pick up the most recent checkpoint.

## Launch a Training

### Llama 3.1 8B training

To launch your training for Llama 3.1 8B, run

```bash
sbatch llama3_1_8b-training.sbatch
```

You'll find a new file in the FSDP directory of the form `llama3_1_8b-FSDP_[JOB ID].out`. This will be continuously updated with your training logs. Don't be worried if you see a long stream of NCCL logs (we prefer to use `NCCL_DEBUG=INFO` for verbose logging). After about a minute, you should see your model training, with an output similar to below for Llama3.1 8B:

```text
+ TORCHRUN_ARGS=('--nproc_per_node=8' '--nnodes=2' '--rdzv_id=98' '--rdzv_backend=c10d' '--rdzv_endpoint=p5-dy-gpu-1')
+ declare -a TORCHRUN_ARGS
+ export TORCHRUN=torchrun
+ TORCHRUN=torchrun
+ export TRAIN_SCRIPT=../src/train.py
+ TRAIN_SCRIPT=../src/train.py
+ TRAINING_ARGS=('--max_context_width=128256' '--num_key_value_heads=8' '--intermediate_size=14336' '--hidden_width=4096' '--num_layers=32' '--num_heads=32' '--model_type=llama_v3' '--tokenizer=hf-internal-testing/llama-tokenizer' '--checkpoint_freq=5000' '--validation_freq=500' '--max_steps=5000' '--checkpoint_dir=./checkpoints' '--dataset=allenai/c4' '--dataset_config_name=en' '--resume_from_checkpoint=./checkpoints' '--train_batch_size=1' '--val_batch_size=1' '--sharding_strategy=full' '--offload_activations=1')
+
...
0: 2025-06-10 13:25:51 I [train.py:156] Creating Model
0: 2025-06-10 13:27:04 I [train.py:172] Created model with total parameters: 7392727040 (7.39 B)
...
0: 2025-06-10 13:29:17 I [train.py:103] Batch 34 Loss: 7.96630, Speed: 5.80 samples/sec, lr: 0.000100
0: 2025-06-10 13:29:20 I [train.py:103] Batch 35 Loss: 8.04526, Speed: 5.21 samples/sec, lr: 0.000100
0: 2025-06-10 13:29:23 I [train.py:103] Batch 36 Loss: 7.20530, Speed: 5.28 samples/sec, lr: 0.000100
0: 2025-06-10 13:29:26 I [train.py:103] Batch 37 Loss: 7.86750, Speed: 5.37 samples/sec, lr: 0.000100
0: 2025-06-10 13:29:29 I [train.py:103] Batch 38 Loss: 8.02228, Speed: 5.78 samples/sec, lr: 0.000100
0: 2025-06-10 13:29:32 I [train.py:103] Batch 39 Loss: 7.86903, Speed: 5.78 samples/sec, lr: 0.000100
0: 2025-06-10 13:29:34 I [train.py:103] Batch 40 Loss: 6.80665, Speed: 5.79 samples/sec, lr: 0.000100
0: 2025-06-10 13:29:37 I [train.py:103] Batch 41 Loss: 8.44204, Speed: 5.41 samples/sec, lr: 0.000100
0: 2025-06-10 13:29:40 I [train.py:103] Batch 42 Loss: 7.88105, Speed: 5.79 samples/sec, lr: 0.000100
0: 2025-06-10 13:29:43 I [train.py:103] Batch 43 Loss: 7.38831, Speed: 5.54 samples/sec, lr: 0.000100
```


### Note on launching Mistral 8x7B/Mathstral 7B

Mistral models have gated access on HuggingFace hence you will need to first to review the terms of usage of [Mistral 8x7B](https://huggingface.co/mistralai/Mixtral-8x7B-v0.1) and [Mathstral 7B](https://huggingface.co/mistralai/Mistral-7B-v0.1) before launching their trainings.

You then need to create a [user access token](https://huggingface.co/docs/hub/en/security-tokens) to access the gated models. 

Once created you will need to define it in your environment:

```bash
export HF_TOKEN=<YOUR TOKEN>
```

You are now ready to launch your training for Mistral 8x7B with the following command:

```bash
sbatch mistral_8x7b-training.sbatch
```

You'll find a new file in the FSDP directory of the form `mistral_8x7b-FSDP_[JOB ID].out`.

If you need to cancel or modify your job, see the Slurm commands available in the [Slurm documentation](https://slurm.schedmd.com/quickstart.html).
