# Get Started Training Llama 2 with PyTorch FSDP in 5 Minutes

These scripts provide an easy way to get started with multinode [FSDP](https://pytorch.org/tutorials/intermediate/FSDP_tutorial.html) training on Slurm. It is designed to be as simple as possible, requires no data preparation, and uses a simple Conda environment. 

## 0. Prerequisites

Before running this training, you'll need to create a Slurm cluster with an FSx for Lustre file system. Instructions can be found in [1.architectures](../../1.architectures).

## 1. Create Environment

On your cluster head node, navigate to your shared FSx for Lustre file system, and clone this repo. If you followed the tutorial linked above, it will be location at `/fsx`.

```
cd /fsx
git clone https://github.com/aws-samples/awsome-distributed-training/
cd awsome-distributed-training/3.test_cases/10.FSDP
```

Next, run the `0.create_conda_env.sh` script. This script will first download and install [Miniconda](https://docs.conda.io/projects/miniconda/en/latest/), then create a Conda env called `pt_fsdp`.

```
bash 0.create_conda_env.sh
```

By creating this environment on the shared FSx for Lustre volume, all compute nodes in our cluster will have access to it.

## 2. Data

For this example, we'll be using the [C4 dataset](https://huggingface.co/datasets/allenai/c4). Because C4 is several hundred gigabytes, we'll stream the data directly from [HuggingFace](https://huggingface.co/datasets). The `create_streaming_dataloaders` function in `train.py` is already setup to do this, so there's no data prep required for running this training. If you'd like to instead use your own dataset, you can do so by [formatting it as a HuggingFace dataset](https://huggingface.co/docs/datasets/create_dataset), and passing its location to the `--dataset_path` argument.

## 3. Launch Training

The script to launch a Slurm batch training job can be found in `1.distributed_training.sbatch`. You can adjust the number of training nodes by modifying `#SBATCH --nodes=4`. You can also adjust the training parameters in `TRAINING_ARGS`. Additional parameters can be found in `model/arguments.py`. Note that we use the same directory for both `--checkpoint_dir` and `--resume_from_checkpoint`. If there are multiple checkpoints, `--resume_from_checkpoint` will automatically select the most recent one. This way if our training is interupted for any reason, it will automatically pick up the most recent checkpoint.

```
declare -a TRAINING_ARGS=(
    --num_key_value_heads=32 \
    --llama_intermediate_size=11008 \
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

You'll find a new file in the FSDP directory of the form `slurm-[job-number].out`. This will be continuously updated with your training logs. To stop training, get your job number using `squeue` and run `scancel [job-number]`.
