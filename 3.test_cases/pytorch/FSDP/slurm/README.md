# Running PyTorch FSDP with Slurm

The following content provides guidance on how to run PyTorch FSDP on a Slurm cluster using the common crawl dataset.

## Retrieve the guidance on your cluster

On your cluster head node,
1. Navigate to your shared FSx for Lustre file system.
* If you followed the tutorial linked above, it will be location at `/fsx`.
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

## Data

For this example, you'll be using the [C4 dataset](https://huggingface.co/datasets/allenai/c4), which is several hundred gigabytes. Instead of downloading the whole thing, the `create_streaming_dataloaders` function will stream the dataset from [HuggingFace](https://huggingface.co/datasets), so there's no data prep required for running this training.

If you'd like to instead use your own dataset, you can do so by [formatting it as a HuggingFace dataset](https://huggingface.co/docs/datasets/create_dataset), and passing its location to the `--dataset_path` argument.

## Launch Training

In this solution, you will find FSDP training examples for Llama2 (7B, 13B, 70B), Mistral 8x&b and Mistral Mathstral.
You can adjust the number of training nodes by modifying `#SBATCH --nodes=4` to match the size of your cluster.

If you are using non-EFA enabled instances, such as G4dn, or single GPU g5 nodes, comment out all EFA environment variables on lines 24-25.

Also, under `User Variables` make sure to adjust `GPUS_PER_NODE` to match the number of GPUs on your instance type (8 for P4d(e)/P5, 4 for G5.12xlarge, 1 for G5.xlarge).

You can also adjust the training parameters in `TRAINING_ARGS` (for example, to increase batch size). Additional parameters can be found in `model/arguments.py`. Note that we use the same directory for both `--checkpoint_dir` and `--resume_from_checkpoint`. If there are multiple checkpoints, `--resume_from_checkpoint` will automatically select the most recent one. This way if our training is interupted for any reason, it will automatically pick up the most recent checkpoint.

### Llama 2 7B training

To launch your training for Llama2 7B, run

```bash
sbatch llama2_7b-training.sbatch
```

You'll find a new file in the FSDP directory of the form `llama2_7b-FSDP_[JOB ID].out`. This will be continuously updated with your training logs. Don't be worried if you see a long stream of NCCL logs (we prefer to use `NCCL_DEBUG=INFO` for verbose logging). After about a minute, you should see your model training, with an output similar to below for Llama2 :

```text
+ TORCHRUN_ARGS=('--nproc_per_node=8' '--nnodes=4' '--rdzv_id=2513' '--rdzv_backend=c10d' '--rdzv_endpoint=p5-dy-gpu-1')
+ TORCHRUN=torchrun
+ export TRAIN_SCRIPT=./train.py
+ TRAIN_SCRIPT=./train.py
+ TRAINING_ARGS=('--max_context_width=4096' '--num_key_value_heads=32' '--intermediate_size=11008' '--hidden_width=4096' '--num_layers=32' '--num_heads=32' '--model_type=llama_v2' '--tokenizer=hf-internal-testing/llama-tokenizer' '--checkpoint_freq=5000' '--validation_freq=500' '--max_steps=5000' '--checkpoint_dir=./checkpoints' '--dataset=c4' '--dataset_config_name=en' '--resume_from_checkpoint=./checkpoints' '--train_batch_size=1' '--val_batch_size=1' '--sharding_strategy=full' '--offload_activations=1')
...
0: 2025-04-04 19:56:52 I [train.py:156] Creating Model
0: 2025-04-04 19:57:57 I [train.py:172] Created model with total parameters: 6889410560 (6.89 B)
...
1: p5-dy-gpu-2:62571:62571 [1] NCCL INFO NCCL version 2.26.2+cuda12.2
1: p5-dy-gpu-2:62574:62574 [4] NCCL INFO cudaDriverVersion 12040
2: p5-dy-gpu-3:60823:61204 [2] NCCL INFO NET/OFI Initializing aws-ofi-nccl 1.14.0
2: p5-dy-gpu-3:60823:61204 [2] NCCL INFO NET/OFI Using Libfabric version 1.22
...
0: 2025-04-04 19:58:26 I [train.py:103] Batch 0 Loss: 11.63327, Speed: 2.80 samples/sec, lr: 0.000006
0: 2025-04-04 19:58:28 I [train.py:103] Batch 1 Loss: 11.64674, Speed: 17.06 samples/sec, lr: 0.000013
0: 2025-04-04 19:58:30 I [train.py:103] Batch 2 Loss: 11.56934, Speed: 17.61 samples/sec, lr: 0.000019
0: 2025-04-04 19:58:32 I [train.py:103] Batch 3 Loss: 11.30075, Speed: 17.66 samples/sec, lr: 0.000025
0: 2025-04-04 19:58:33 I [train.py:103] Batch 4 Loss: 11.00539, Speed: 17.66 samples/sec, lr: 0.000031
0: 2025-04-04 19:58:35 I [train.py:103] Batch 5 Loss: 10.39471, Speed: 17.28 samples/sec, lr: 0.000038
```

###  Mistral 8x7B

To run Mistral 8x7B model, you will need first to review the terms of usage on [HuggingFace](https://huggingface.co/mistralai/Mixtral-8x7B-v0.1).
Then you will need to create a [user access token](https://huggingface.co/docs/hub/en/security-tokens) to access the gated Mathstral 7B model.
Once created you will need to define it in your environment:

```bash
export HF_TOKEN=>YOUR TOKEN>
```

You are now ready to launch your training for Mistral 8x7B with the following command:

```bash
sbatch mistral_8x7b-training.sbatch
```

You'll find a new file in the FSDP directory of the form `mistral_8x7b-FSDP_[JOB ID].out`. This will be continuously updated with your training logs. Don't be worried if you see a long stream of NCCL logs (we prefer to use `NCCL_DEBUG=INFO` for verbose logging). After about a minute, you should see your model training, with an output similar to below for Mistral:

```text
...
+ export TORCHRUN=torchrun
+ TORCHRUN=torchrun
+ export TRAIN_SCRIPT=./train.py
+ TRAIN_SCRIPT=./train.py
+ TRAINING_ARGS=('--train_batch_size=4' '--val_batch_size=4' '--max_steps=5000' '--seed=42' '--bf16=1' '--grad_clip=1.0' '--weight_decay=0.2' '--beta1=0.9' '--beta2=0.95' '--activation_checkpointing=1' '--intermediate_size=14336' '--num_key_value_heads=8' '--logging_freq=1' '--max_context_width=32768' '--vocab_size=32000' '--hidden_width=4096' '--num_layers=32' '--num_heads=32' '--resid_pdrop=0.1' '--embd_pdrop=0.1' '--attn_pdrop=0.1' '--summary_first_pdrop=0.1' '--initializer_range=0.02' '--model_type=mixtral' '--rotary_pct=0.25' '--rotary_emb_base=10000' '--lr=0.0001' '--lr_decay_style=cosine' '--min_lr=1e-5' '--warmup=0.0032' '--plateau=0.0' '--dataset=allenai/c4' '--tokenizer=mistralai/Mixtral-8x7B-v0.1' '--epochs=3' '--dataset_config_name=en' '--limit_all_gathers=1' '--sharding_strategy=full' ' #' 'https://pytorch.org/docs/stable/fsdp.html' '--offload_activations=1')
+ declare -a TRAINING_ARGS
...
0: 2025-04-11 16:49:59 I [train.py:156] Creating Model
0: 2025-04-11 16:57:23 I [train.py:172] Created model with total parameters: 46702792704 (46.70 B)
0: 2025-04-11 16:57:56 I [train.py:216] Wrapped model with FSDP
0: 2025-04-11 16:57:56 I [train.py:233] Created optimizer
...
1: p5-dy-gpu-2:62571:62571 [1] NCCL INFO NCCL version 2.26.2+cuda12.2
1: p5-dy-gpu-2:62574:62574 [4] NCCL INFO cudaDriverVersion 12040
2: p5-dy-gpu-3:60823:61204 [2] NCCL INFO NET/OFI Initializing aws-ofi-nccl 1.14.0
2: p5-dy-gpu-3:60823:61204 [2] NCCL INFO NET/OFI Using Libfabric version 1.22
...
0: 2025-04-11 16:58:41 I [train.py:103] Batch 0 Loss: 11.21702, Speed: 6.19 samples/sec, lr: 0.000006
0: 2025-04-11 16:58:49 I [train.py:103] Batch 1 Loss: 11.20650, Speed: 14.51 samples/sec, lr: 0.000013
0: 2025-04-11 16:58:58 I [train.py:103] Batch 2 Loss: 11.12571, Speed: 15.06 samples/sec, lr: 0.000019
0: 2025-04-11 16:59:07 I [train.py:103] Batch 3 Loss: 10.97558, Speed: 14.70 samples/sec, lr: 0.000025
0: 2025-04-11 16:59:15 I [train.py:103] Batch 4 Loss: 10.82548, Speed: 14.48 samples/sec, lr: 0.000031
0: 2025-04-11 16:59:24 I [train.py:103] Batch 5 Loss: 10.31511, Speed: 14.50 samples/sec, lr: 0.000038
```

###  Mistral Mathstral 7B

To run Mistral Mathstral 7B model, you will need first to review the terms of usage on [HuggingFace](https://huggingface.co/mistralai/Mistral-7B-v0.1).
Then you will need to create a [user access token](https://huggingface.co/docs/hub/en/security-tokens) to access the gated Mathstral 7B model.
Once created you will need to define it in your environment:

```bash
export HF_TOKEN=>YOUR TOKEN>
```

You are now ready to launch your training for Mathstral 7B with the following command:

```bash
sbatch mathstral_7b-training.sbatch
```

For Mathstral, your output should look similar to the one below:

```text
...
+ TORCHRUN_ARGS=('--nproc_per_node=8' '--nnodes=4' '--rdzv_id=2515' '--rdzv_backend=c10d' '--rdzv_endpoint=p5-dy-gpu-1')
+ declare -a TORCHRUN_ARGS
+ export TORCHRUN=torchrun
+ TORCHRUN=torchrun
+ export TRAIN_SCRIPT=./train.py
+ TRAIN_SCRIPT=./train.py
+ TRAINING_ARGS=('--train_batch_size=1' '--val_batch_size=1' '--max_steps=5000' '--seed=42' '--grad_clip=1.0' '--weight_decay=0.2' '--beta1=0.9' '--beta2=0.95' '--activation_checkpointing=1' '--intermediate_size=14336' '--num_key_value_heads=8' '--logging_freq=1' '--max_context_width=32768' '--vocab_size=32768' '--hidden_width=4096' '--num_layers=32' '--num_heads=32' '--resid_pdrop=0.1' '--embd_pdrop=0.1' '--attn_pdrop=0.1' '--summary_first_pdrop=0.1' '--initializer_range=0.02' '--model_type=mistral' '--rotary_pct=0.25' '--rotary_emb_base=10000' '--lr=0.0001' '--lr_decay_style=cosine' '--min_lr=1e-5' '--warmup=0.0032' '--plateau=0.0' '--dataset=allenai/c4' '--tokenizer=mistralai/mathstral-7B-v0.1' '--epochs=3' '--checkpoint_dir=./checkpoints/mathstral-7B' '--resume_from_checkpoint=./checkpoints/mathstral-7B' '--checkpoint_freq=50' '--validation_freq=500' '--dataset_config_name=en' '--limit_all_gathers=1' '--sharding_strategy=full' ' #' 'https://pytorch.org/docs/stable/fsdp.html' '--offload_activations=1')
...
1: p5-dy-gpu-2:62571:62571 [1] NCCL INFO NCCL version 2.26.2+cuda12.2
1: p5-dy-gpu-2:62574:62574 [4] NCCL INFO cudaDriverVersion 12040
2: p5-dy-gpu-3:60823:61204 [2] NCCL INFO NET/OFI Initializing aws-ofi-nccl 1.14.0
2: p5-dy-gpu-3:60823:61204 [2] NCCL INFO NET/OFI Using Libfabric version 1.22
...
0: 2025-04-07 22:04:23 I [train.py:156] Creating Model
0: 2025-04-07 22:05:30 I [train.py:172] Created model with total parameters: 7248023552 (7.25 B)
0: 2025-04-07 22:05:40 I [train.py:216] Wrapped model with FSDP
0: 2025-04-07 22:05:40 I [train.py:233] Created optimizer
...
0: 2025-04-07 22:06:15 I [train.py:103] Batch 0 Loss: 11.21489, Speed: 2.61 samples/sec, lr: 0.000006
0: 2025-04-07 22:06:17 I [train.py:103] Batch 1 Loss: 11.20829, Speed: 15.37 samples/sec, lr: 0.000013
0: 2025-04-07 22:06:19 I [train.py:103] Batch 2 Loss: 11.15640, Speed: 14.87 samples/sec, lr: 0.000019
0: 2025-04-07 22:06:21 I [train.py:103] Batch 3 Loss: 10.90571, Speed: 15.45 samples/sec, lr: 0.000025
0: 2025-04-07 22:06:24 I [train.py:103] Batch 4 Loss: 10.60309, Speed: 15.35 samples/sec, lr: 0.000031
0: 2025-04-07 22:06:25 I [train.py:103] Batch 5 Loss: 10.02562, Speed: 16.59 samples/sec, lr: 0.000038
```

## References
Llama2 models parameters based on the values in the [Llama 2 paper](https://arxiv.org/abs/2307.09288).

| Param                    |     7B      |     13B     |     70B     |
| ------------------------ | ----------- | ----------- | ----------- |
| intermediate_size        | 11008       | 13824       | 28672       |
| num_key_value_heads      | 32          | 40          | 8           |
| hidden_width             | 4096        | 5120        | 8192        |
| num_layers               | 32          | 40          | 80          |
| num_heads                | 32          | 40          | 64          |

If you need to cancel or modify your job, see the Slurm commands available in the [Slurm documentation](https://slurm.schedmd.com/quickstart.html).
