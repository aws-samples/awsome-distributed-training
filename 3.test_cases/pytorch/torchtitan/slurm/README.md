## Setup Instructions

### 0. Prerequisites

Before running this training, you'll need to create a Slurm cluster with an FSx for Lustre file system. Instructions can be found in [1.architectures](../../../1.architectures). Float8 data types are natively supported in NVIDIA H100 and subsequent generations hence it is recommended to run this on at least 1 x p5/p5e/p5en.48xlarge instance. The [Performance Numbers](#performance-numbers) reported in the later sections are based on 4 x p5.48xlarge instances.


### 1. Create torchtitan Conda Environment

On your cluster head node, run the `0.create_conda_env.sh` script:

```bash
bash 0.create_conda_env.sh
```

This script:
- Downloads and installs Miniconda and creates a torchtian conda environment named "pt_torchtitan"
- Clones the torchtitan repository from GitHub 
- Installs all required dependencies including PyTorch nightly build with CUDA support and [torchao library](https://github.com/pytorch/ao) for FP8 support


### 2. Download the Tokenizer

First, create a Hugging Face account to retrieve a [token](https://huggingface.co/settings/tokens.). Log in to your account and create an access token from Hugging Face Tokens. Then apply for Llama3.1 weight access from [Meta-Llama-3.1-8B](https://huggingface.co/meta-llama/Llama-3.1-8B) page.

Use the following command to download the Meta Llama 3 tokenizer:

```bash
cd torchtitan
python scripts/download_tokenizer.py --repo_id meta-llama/Meta-Llama-3.1-8B --tokenizer_path "original" --hf_token=YOUR_HF_TOKEN_HERE
```

The tokenizer will be downloaded to `torchtitan/assets/tokenizer/original`. Ensure that you update the tokenizer path in the training config TOML file, for example:

```
tokenizer_path = "./torchtitan/assets/tokenizer/original/tokenizer.model"
```

### 3. Launch Distributed Training

The provided SLURM batch script configures and launches distributed training:

```bash
sbatch 1.llama_3_8b_torchtitan.sh
```

This script:
- Sets the path to the torchtitan training script: `./torchtitan/torchtitan/train.py`
- Uses the default Llama 3 8B configuration: `./torchtitan/torchtitan/models/llama/train_configs/llama3_8b.toml`
- Launches distributed training on your cluster

The training will log metrics including loss, throughput, memory utilization, and MFU (Model FLOPS Utilization) to help monitor training efficiency.

## Performance Numbers

Running the llama3_8b.toml default configuration in torchtitan/models/llama/train_configs on 4 x p5.48xlarge instances (each instance contains 8 x H100 GPUs)

```bash
1: 2025-03-04 00:44:44,441 - root - INFO - [36mstep: 1990  [32mloss:  3.4370  [33mmemory: 68.57GiB(86.69%)  [34mtps: 6,785  [35mmfu: 39.73%[39m
0: 2025-03-04 00:44:44,441 - root - INFO - [36mstep: 1990  [32mloss:  3.4370  [33mmemory: 68.57GiB(86.69%)  [34mtps: 6,785  [35mmfu: 39.73%[39m
0: 2025-03-04 00:44:44,441 - root - INFO - [36mstep: 1990  [32mloss:  3.4370  [33mmemory: 68.57GiB(86.69%)  [34mtps: 6,785  [35mmfu: 39.73%[39m
3: 2025-03-04 00:44:44,441 - root - INFO - [36mstep: 1990  [32mloss:  3.4370  [33mmemory: 68.57GiB(86.69%)  [34mtps: 6,785  [35mmfu: 39.73%[39m
2: 2025-03-04 00:44:44,441 - root - INFO - [36mstep: 1990  [32mloss:  3.4370  [33mmemory: 68.57GiB(86.69%)  [34mtps: 6,785  [35mmfu: 39.73%[39m
2: 2025-03-04 00:44:44,441 - root - INFO - [36mstep: 1990  [32mloss:  3.4370  [33mmemory: 68.57GiB(86.69%)  [34mtps: 6,785  [35mmfu: 39.73%[39m
2: 2025-03-04 00:44:44,441 - root - INFO - [36mstep: 1990  [32mloss:  3.4370  [33mmemory: 68.57GiB(86.69%)  [34mtps: 6,785  [35mmfu: 39.73%[39m
3: 2025-03-04 00:44:44,441 - root - INFO - [36mstep: 1990  [32mloss:  3.4370  [33mmemory: 68.57GiB(86.69%)  [34mtps: 6,785  [35mmfu: 39.73%[39m
2: 2025-03-04 00:44:44,441 - root - INFO - [36mstep: 1990  [32mloss:  3.4370  [33mmemory: 68.57GiB(86.69%)  [34mtps: 6,785  [35mmfu: 39.73%[39m
```


## Performance Optimizations

To apply various optimizations that leverage `torch.compile` and FP8 for improved performance, update these entries in your training config file:

```toml
compile = true
...
...

[float8]
enable_float8_linear = true
enable_fsdp_float8_all_gather = true
precompute_float8_dynamic_scale_for_fsdp = true
```

Applying these optimizations to the llama3_8b.toml config and running on the 4 x p5.48xlarge instances we observe improved throughput(**15.92%** improvement) and MFU metrics(**from 39.73% -> 46.06%**) compared to the default configuration:

```bash
2: 2025-03-04 00:31:19,918 - root - INFO - [36mstep: 1990  [32mloss:  3.4255  [33mmemory: 63.48GiB(80.25%)  [34mtps: 7,865  [35mmfu: 46.06%[39m
0: 2025-03-04 00:31:19,918 - root - INFO - [36mstep: 1990  [32mloss:  3.4255  [33mmemory: 63.48GiB(80.25%)  [34mtps: 7,865  [35mmfu: 46.06%[39m
1: 2025-03-04 00:31:19,918 - root - INFO - [36mstep: 1990  [32mloss:  3.4255  [33mmemory: 63.48GiB(80.25%)  [34mtps: 7,865  [35mmfu: 46.06%[39m
1: 2025-03-04 00:31:19,918 - root - INFO - [36mstep: 1990  [32mloss:  3.4255  [33mmemory: 63.48GiB(80.25%)  [34mtps: 7,865  [35mmfu: 46.06%[39m
3: 2025-03-04 00:31:19,918 - root - INFO - [36mstep: 1990  [32mloss:  3.4255  [33mmemory: 63.48GiB(80.25%)  [34mtps: 7,865  [35mmfu: 46.06%[39m
2: 2025-03-04 00:31:19,918 - root - INFO - [36mstep: 1990  [32mloss:  3.4255  [33mmemory: 63.48GiB(80.25%)  [34mtps: 7,865  [35mmfu: 46.06%[39m
2: 2025-03-04 00:31:19,918 - root - INFO - [36mstep: 1990  [32mloss:  3.4255  [33mmemory: 63.48GiB(80.25%)  [34mtps: 7,865  [35mmfu: 46.06%[39m
0: 2025-03-04 00:31:19,918 - root - INFO - [36mstep: 1990  [32mloss:  3.4255  [33mmemory: 63.48GiB(80.25%)  [34mtps: 7,865  [35mmfu: 46.06%[39m
0: 2025-03-04 00:31:19,918 - root - INFO - [36mstep: 1990  [32mloss:  3.4255  [33mmemory: 63.48GiB(80.25%)  [34mtps: 7,865  [35mmfu: 46.06%[39m
```

