# Get Started Training Llama 2 and Mixtral with PyTorch FSDP in 5 Minutes

These scripts provide an easy way to get started with multinode [FSDP](https://pytorch.org/tutorials/intermediate/FSDP_tutorial.html) training on Slurm. It is designed to be as simple as possible, requires no data preparation, and uses a simple Conda environment. 

## 0. Prerequisites

Before running this training, you'll need to create a Slurm cluster with an FSx for Lustre file system. Instructions can be found in [1.architectures](../../1.architectures).

## 1. Create Environment

On your cluster head node, 
1. Navigate to your shared FSx for Lustre file system.
* If you followed the tutorial linked above, it will be location at `/fsx`.   
2. Clone this repo. 

```
cd /fsx
git clone https://github.com/aws-samples/awsome-distributed-training/
cd awsome-distributed-training/3.test_cases/10.FSDP
```

3. Run the `0.create_conda_env.sh` script. 
* This script will first download and install [Miniconda](https://docs.conda.io/projects/miniconda/en/latest/), then create a Conda env called `pt_fsdp`.

```
bash 0.create_conda_env.sh
```

* By creating this environment on the shared FSx for Lustre volume, all compute nodes in our cluster will have access to it.

## 2. Data

For this example, we'll be using the [C4 dataset](https://huggingface.co/datasets/allenai/c4), which is several hundred gigabytes. Instead of downloading the whole thing, the `create_streaming_dataloaders` function will stream the dataset from [HuggingFace](https://huggingface.co/datasets), so there's no data prep required for running this training. 

If you'd like to instead use your own dataset, you can do so by [formatting it as a HuggingFace dataset](https://huggingface.co/docs/datasets/create_dataset), and passing its location to the `--dataset_path` argument.

## 3. Launch Training

The script to launch a Llama 2 Slurm batch training job can be found in `1.distributed_training.sbatch`. The script to launch a Mixtral training can be found in `2.distrbiuted_training_mixtral.sbatch` You can adjust the number of training nodes by modifying `#SBATCH --nodes=4`. 

If you are using a non-RDMA enable instance, such as G5.12x, comment out lines 21-22. These instances have EFA between nodes, but do not have the GPU direct RDMA access of P4d and P5 instances.

```
## Plenty of EFA level variables
## Comment out for non-efa instances (G5, G4d, P3)
# export FI_EFA_USE_DEVICE_RDMA=1 # use for p4d
# export FI_EFA_FORK_SAFE=1
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa
export NCCL_DEBUG=INFO
```

If you are using non-EFA enabled instances, such as G4dn, or single GPU G5 nodes, comment out all EFA environment variables on lines 21-25.

Also, under `User Variables` make sure to adjust `GPUS_PER_NODE` to match the number of GPUs on your instance type (8 for P4d/P5, 4 for G5.12xlarge, 1 for G5.xlarge).

You can also adjust the training parameters in `TRAINING_ARGS` (for example, to train Llama 2 70b). Additional parameters can be found in `model/arguments.py`. Note that we use the same directory for both `--checkpoint_dir` and `--resume_from_checkpoint`. If there are multiple checkpoints, `--resume_from_checkpoint` will automatically select the most recent one. This way if our training is interupted for any reason, it will automatically pick up the most recent checkpoint.

```
declare -a TRAINING_ARGS=(
    --num_key_value_heads=32 \
    --intermediate_size=11008 \
    --max_context_width=4096 \
    --hidden_width=4096 \
    --num_layers=32 \
    --num_heads=32 \
    --model_type=llama_v2 \
    --checkpoint_freq=1000 \
    --validation_freq=500 \
    --checkpoint_dir=./checkpoints \
    --resume_from_checkpoint=./checkpoints
)
```

To launch your training, run

```
sbatch 1.distributed_training.sbatch
```

You'll find a new file in the FSDP directory of the form `slurm-[job-number].out`. This will be continuously updated with your training logs. Don't be worried if you see a long stream of NCCL logs (we prefer to use `NCCL_DEBUG=INFO` for verbose logging). After about a minute, you should see your model training, with an output similar to below.

```
+ TORCHRUN=./pt_fsdp/bin/torchrun
+ export TRAIN_SCRIPT=./train.py
+ TRAIN_SCRIPT=./train.py
+ TRAINING_ARGS=(--max_context_width=4096 --num_key_value_heads=32 \ # 7b: 32 13b: 40 70b: 8 --intermediate_size=11008 \ # 7b: 11008 13b: 13824 70b: 28672 --hidden_width=4096 \ # 7b: 4096 13b: 5120 70b: 8192 --num_layers=32 \ # 7b: 32 13b: 40 70b: 80 --num_heads=32 \ # 7b: 32 13b: 40 70b: 64 --model_type=llama_v2 --checkpoint_freq=50 --validation_freq=500 --checkpoint_dir=./checkpoints --resume_from_checkpoint=./checkpoints)
...
0: 2023-11-29 04:17:52 I [train.py:175] Creating Model
0: 2023-11-29 04:19:17 I [train.py:182] Created model with total parameters: 6889410560 (6.89 B)
0: 2023-11-29 04:19:28 I [train.py:209] Wrapped model with FSDP
0: 2023-11-29 04:19:28 I [train.py:226] Created optimizer
...
2: ip-10-1-41-139:6171:8092 [0] NCCL INFO NET/OFI Initializing aws-ofi-nccl 1.7.3-aws
3: ip-10-1-44-54:6168:6168 [7] NCCL INFO cudaDriverVersion 12020
0: ip-10-1-14-81:6158:9214 [2] NCCL INFO NET/OFI Selected Provider is efa (found 4 nics)
...
0: ip-10-1-14-81:6158:9214 [2] NCCL INFO comm 0x8b6b550 rank 2 nranks 32 cudaDev 2 busId 201c0 - Init COMPLETE
0: ip-10-1-14-81:6157:9213 [1] NCCL INFO comm 0x8494480 rank 1 nranks 32 cudaDev 1 busId 101d0 - Init COMPLETE
0: 2023-11-29 04:19:48 I [train.py:122] Batch 0 Loss: 11.6533041, Speed: 3.98 samples/sec, lr: 0.000006
0: 2023-11-29 04:19:54 I [train.py:122] Batch 1 Loss: 11.620493, Speed: 10.72 samples/sec, lr: 0.000013
0: 2023-11-29 04:20:00 I [train.py:122] Batch 2 Loss: 11.3152923, Speed: 10.71 samples/sec, lr: 0.000019
0: 2023-11-29 04:20:06 I [train.py:122] Batch 3 Loss: 10.461415, Speed: 10.11 samples/sec, lr: 0.000025
0: 2023-11-29 04:20:12 I [train.py:122] Batch 4 Loss: 11.8934202, Speed: 10.71 samples/sec, lr: 0.000031
0: 2023-11-29 04:20:18 I [train.py:122] Batch 5 Loss: 13.9545879, Speed: 10.70 samples/sec, lr: 0.000038
```

To modify training for a 13 or 70B Llama 2 model, just change the corresponding parameters based on the values in the [Llama 2 paper](https://arxiv.org/abs/2307.09288).

| Param                    |     7B      |     13B     |     70B     |
| ------------------------ | ----------- | ----------- | ----------- |
| intermediate_size        | 11008       | 13824       | 28672       |
| num_key_value_heads      | 32          | 40          | 8           |
| hidden_width             | 4096        | 5120        | 8192        |
| num_layers               | 32          | 40          | 80          |
| num_heads                | 32          | 40          | 64          |

If you need to cancel or modify your job, see the Slurm commands available in the [Slurm documentation](https://slurm.schedmd.com/quickstart.html).