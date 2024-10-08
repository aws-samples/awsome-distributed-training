# Get Started Training Llama 2, Mixtral 8x7B, and Mistral Mathstral with PyTorch FSDP in 5 Minutes

These scripts provide an easy way to get started with multinode [FSDP](https://pytorch.org/tutorials/intermediate/FSDP_tutorial.html) training on Slurm. It is designed to be as simple as possible, requires no data preparation, and uses a simple Conda environment. If you would like to run FSDP on EKS, please refer to [README-EKS.md](README-EKS.md).

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

- The script to launch a Llama 2 Slurm batch training job can be found in `1.distributed-training-llama2.sbatch`.
- The script to launch a Mixtral training can be found in `2.distributed-training-mixtral.sbatch`.
- Th script to launch Mistral Mathstral training can be foudn in `3.distributed-training-mistral-mathstral.sbatch`.
-  You can adjust the number of training nodes by modifying `#SBATCH --nodes=4` to match the size of your cluster.

If you are using non-EFA enabled instances, such as G4dn, or single GPU g5 nodes, comment out all EFA environment variables on lines 24-25.

Also, under `User Variables` make sure to adjust `GPUS_PER_NODE` to match the number of GPUs on your instance type (8 for P4d(e)/P5, 4 for G5.12xlarge, 1 for G5.xlarge).

You can also adjust the training parameters in `TRAINING_ARGS` (for example, to train Llama 2 70b). Additional parameters can be found in `model/arguments.py`. Note that we use the same directory for both `--checkpoint_dir` and `--resume_from_checkpoint`. If there are multiple checkpoints, `--resume_from_checkpoint` will automatically select the most recent one. This way if our training is interupted for any reason, it will automatically pick up the most recent checkpoint.

Llama 2 training args

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
Mistral Mathstral training args 

```
declare -a TRAINING_ARGS=(
    --train_batch_size=1 \
    --val_batch_size=1 \
    --max_steps=5000 \
    --seed=42 \
    --grad_clip=1.0 \
    --weight_decay=0.2 \
    --beta1=0.9 \
    --beta2=0.95 \
    --activation_checkpointing=1 \
    --intermediate_size=14336 \
    --num_key_value_heads=8 \
    --logging_freq=1 \
    --max_context_width=32768 \
    --vocab_size=32768 \
    --hidden_width=4096 \
    --num_layers=32 \
    --num_heads=32 \
    --resid_pdrop=0.1 \
    --embd_pdrop=0.1 \
    --attn_pdrop=0.1 \
    --summary_first_pdrop=0.1 \
    --initializer_range=0.02 \
    --model_type="mistral" \
    --rotary_pct=0.25 \
    --rotary_emb_base=10000 \
    --lr=0.0001 \
    --lr_decay_style="cosine" \
    --min_lr=1e-5 \
    --warmup=0.0032 \
    --plateau=0.0 \
    --dataset="c4" \
    --tokenizer="mistralai/mathstral-7B-v0.1" \
    --epochs=3 \
    --checkpoint_dir="./checkpoints/mathstral-7B" \
    --resume_from_checkpoint="./checkpoints/mathstral-7B" \
    --checkpoint_freq=50 \
    --validation_freq=500 \
    --dataset_config_name="en" \
    --limit_all_gathers=1 \
    --sharding_strategy="full" \ # https://pytorch.org/docs/stable/fsdp.html
    --offload_activations=1
)

```
To launch your training for Llama 2, run

```
sbatch 1.distributed-training-llama2.sbatch 
```
Similarly for Mixtral 8x7B and Mathstral, launch run `sbatch` with the `2.distributed-training-mixtral.sbatch` and the `3.distributed-training-mistral-mathstral.sbatch` files respectively.

You'll find a new file in the FSDP directory of the form `slurm-[job-number].out`. This will be continuously updated with your training logs. Don't be worried if you see a long stream of NCCL logs (we prefer to use `NCCL_DEBUG=INFO` for verbose logging). After about a minute, you should see your model training, with an output similar to below for Llama2 :

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
For Mathstral, your output should look similar to the one below:

```
...
+ TORCHRUN=./pt_fsdp/bin/torchrun
+ export TRAIN_SCRIPT=./train.py
+ TRAIN_SCRIPT=./train.py
+ TRAINING_ARGS=(--train_batch_size=1 --val_batch_size=1 --max_steps=5000 --seed=42 --grad_clip=1.0 --weight_decay=0.2 --beta1=0.9 --beta2=0.95 --activation_checkpointing=1 --intermediate_size=14336 --num_key_value_heads=8 --logging_freq=1 --max_context_width=32768 --vocab_size=32768 --hidden_width=4096 --num_layers=32 --num_heads=32 --resid_pdrop=0.1 --embd_pdrop=0.1 --attn_pdrop=0.1 --summary_first_pdrop=0.1 --initializer_range=0.02 --model_type="mistral" --rotary_pct=0.25 --rotary_emb_base=10000 --lr=0.0001 --lr_decay_style="cosine" --min_lr=1e-5 --warmup=0.0032 --plateau=0.0 --dataset="c4" --tokenizer="mistralai/mathstral-7B-v0.1" --epochs=3 --checkpoint_dir="./checkpoints/mathstral-7B" --resume_from_checkpoint="./checkpoints/mathstral-7B" --checkpoint_freq=50 --validation_freq=500 --dataset_config_name="en" --limit_all_gathers=1 --sharding_strategy="full" \ # https://pytorch.org/docs/stable/fsdp.html --offload_activations=1)
+ declare -a TRAINING_ARGS
+ AUTO_RESUME=
+ '[' -d /opt/sagemaker_cluster ']'
+ echo 'Detected Hyperpod cluster.. enabling --auto-resume=1'
Detected Hyperpod cluster.. enabling --auto-resume=1
+ AUTO_RESUME=--auto-resume=1
+ srun --auto-resume=1 -l ./pt_fsdp/bin/torchrun --nproc_per_node=8 --nnodes=4 --rdzv_id=35 --rdzv_backend=c10d --rdzv_endpoint=ip-10-2-39-253 ./train.py --train_batch_size=1 --val_batch_size=1 --max_steps=5000 --seed=42 --grad_clip=1.0 --weight_decay=0.2 --beta1=0.9 --beta2=0.95 --activation_checkpointing=1 --intermediate_size=14336 --num_key_value_heads=8 --logging_freq=1 --max_context_width=32768 --vocab_size=32768 --hidden_width=4096 --num_layers=32 --num_heads=32 --resid_pdrop=0.1 --embd_pdrop=0.1 --attn_pdrop=0.1 --summary_first_pdrop=0.1 --initializer_range=0.02 --model_type=mistral --rotary_pct=0.25 --rotary_emb_base=10000 --lr=0.0001 --lr_decay_style=cosine --min_lr=1e-5 --warmup=0.0032 --plateau=0.0 --dataset=c4 --tokenizer=mistralai/mathstral-7B-v0.1 --epochs=3 --checkpoint_dir=./checkpoints/mathstral-7B --resume_from_checkpoint=./checkpoints/mathstral-7B --checkpoint_freq=50 --validation_freq=500 --dataset_config_name=en --limit_all_gathers=1 --sharding_strategy=full ' #' https://pytorch.org/docs/stable/fsdp.html --offload_activations=1
...
3: 2024-07-19 03:31:38 I [train.py:155] Creating Model
3: 2024-07-19 03:33:08 I [train.py:171] Created model with total parameters: 7248023552 (7.25 B)
3:...
3: 2024-07-19 03:33:23 I [train.py:209] Wrapped model with FSDP
3: 2024-07-19 03:33:23 I [train.py:226] Created optimizer
3: 2024-07-19 03:33:23 I [checkpoint.py:70] No Checkpoints Found
...
3: 2024-07-19 03:33:35 I [train.py:102] Batch 0 Loss: 11.19900, Speed: 5.10 samples/sec, lr: 0.000006
3: 2024-07-19 03:33:38 I [train.py:102] Batch 1 Loss: 11.18291, Speed: 10.96 samples/sec, lr: 0.000013
3: 2024-07-19 03:33:40 I [train.py:102] Batch 2 Loss: 11.09163, Speed: 11.22 samples/sec, lr: 0.000019
3: 2024-07-19 03:33:43 I [train.py:102] Batch 3 Loss: 10.86621, Speed: 11.19 samples/sec, lr: 0.000025
3: 2024-07-19 03:33:46 I [train.py:102] Batch 4 Loss: 10.58236, Speed: 11.12 samples/sec, lr: 0.000031
3: 2024-07-19 03:33:49 I [train.py:102] Batch 5 Loss: 10.08024, Speed: 11.18 samples/sec, lr: 0.000038
3: 2024-07-19 03:33:52 I [train.py:102] Batch 6 Loss: 10.15507, Speed: 11.23 samples/sec, lr: 0.000044
3: 2024-07-19 03:33:55 I [train.py:102] Batch 7 Loss: 9.97296, Speed: 10.42 samples/sec, lr: 0.000050
3: 2024-07-19 03:33:58 I [train.py:102] Batch 8 Loss: 10.13596, Speed: 11.21 samples/sec, lr: 0.000056
3: 2024-07-19 03:34:01 I [train.py:102] Batch 9 Loss: 9.93156, Speed: 11.10 samples/sec, lr: 0.000063

```
You are also able to modify the `sbatch` file for Mathstral to work with other Mistral models. Refer to the hyperparameters in the `config.json` file for the models on huggingface to update the training args.

To modify training for a 13 or 70B Llama 2 model, just change the corresponding parameters based on the values in the [Llama 2 paper](https://arxiv.org/abs/2307.09288).

| Param                    |     7B      |     13B     |     70B     |
| ------------------------ | ----------- | ----------- | ----------- |
| intermediate_size        | 11008       | 13824       | 28672       |
| num_key_value_heads      | 32          | 40          | 8           |
| hidden_width             | 4096        | 5120        | 8192        |
| num_layers               | 32          | 40          | 80          |
| num_heads                | 32          | 40          | 64          |

If you need to cancel or modify your job, see the Slurm commands available in the [Slurm documentation](https://slurm.schedmd.com/quickstart.html).
