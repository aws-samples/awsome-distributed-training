# Pretraining Mamba State Spaces Models with PyTorch FSDP

These scripts provide an easy way to get started with multinode [FSDP](https://pytorch.org/tutorials/intermediate/FSDP_tutorial.html) pre-training of Mamba State Spaces models on Slurm. Mamba is a new state space model architecture showing promising performance on information-dense data such as language modeling, where previous subquadratic models fall short of Transformers.
It is based on the line of progress on [structured state space models](https://github.com/state-spaces/s4),
with an efficient hardware-aware design and implementation in the spirit of [FlashAttention](https://github.com/Dao-AILab/flash-attention). 

|Num|                                    Mamba State Space Models                                  |
|:-:|:--------------------------------------------------------------------------------------------:|
| 1 |      [Mamba-2.8B](https://huggingface.co/state-spaces/mamba-2.8b-hf)                         |
| 2 |      [Mamba-1.4B](https://huggingface.co/state-spaces/mamba-1.4b-hf)                         |
| 3 |      [Mamba-790m](https://huggingface.co/state-spaces/mamba-790m-hf)                         |
| 4 |      [Mamba-370m](https://huggingface.co/state-spaces/mamba-370m-hf)                         |


This project provides a guide to run [Mamba State Space Models](https://huggingface.co/state-spaces) on AWS ParallelCluster and SageMaker Hyperpod.


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
cd awsome-distributed-training/3.test_cases/20.FSDP-Mamba
```

## 2. Build docker image
We will run this workload as a container, build the docker image and convert it to an Enroot squash file. To build the docker image run:

```
docker build -t ${DOCKER_IMAGE_NAME}:${TAG} .
```

## 3. Convert Docker image to Enroot
Convert the Docker container image to an [Enroot](https://github.com/NVIDIA/enroot) squash file. This step takes a few minutes.
```
enroot import -o mamba-train.sqsh dockerd://${DOCKER_IMAGE_NAME}

```



## 4. Data

We can now download and tokenize our dataset. To tokenize the data, we will access the tokenizer from 'HuggingFace. Next run the following script to download and process the dataset:

```
   python3 get_dataset.py
```
We are now ready to start training.

## 5. Launch Training

Once we have downloaded and tokenized the data, and the squash file has been generated, you can run `01.train.sbatch` script to start model training.

You can adjust the number of training nodes by modifying `#SBATCH --nodes=4`. 

If you are using a non-RDMA enable instance, such as G5.12x, comment out lines 26-27. These instances have EFA between nodes, but do not have the GPU direct RDMA access of P4d and P5 instances.

```
## Plenty of EFA level variables
## Comment out for non-efa instances (G5, G4d, P3)
# export FI_EFA_USE_DEVICE_RDMA=1 # use for p4d
# export FI_EFA_FORK_SAFE=1
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa
export NCCL_DEBUG=INFO
```

If you are using non-EFA enabled instances, such as G4dn, or single GPU G5 nodes, comment out all EFA environment variables on lines 26-29.

Also, under `User Variables` make sure to adjust `GPUS_PER_NODE` to match the number of GPUs on your instance type (8 for P4d/P5, 4 for G5.12xlarge, 1 for G5.xlarge).

You can also adjust the training parameters in `MODEL_ARGS` (for example, to train Mamba 2.8B, change --model_name to `state-spaces/mamba-2.8b`). Additional parameters can be found in `config/train_conf.py`. Note that we use the same directory for both ` --ckpt_load_path` and ` --ckpt_save_path`. If there are multiple checkpoints, ` --ckpt_load_path` will automatically select the most recent one. This way if our training is interupted for any reason, it will automatically pick up the most recent checkpoint.

```
declare -a MODEL_ARGS=(
    --model_name=state-spaces/mamba-130m
    --load_ckpt_path=/fsx/mamba/pretrain/ckpt
    --save_ckpt_path=/fsx/mamba/pretrain/ckpt
    --dataset_path=/fsx/data/wikicorpus_llama2_7B_tokenized_4k
    --fsdp_activation_checkpointing=True
    --selective_checkpointing=1
    --sharding_strategy=fsdp
    --batch_size=2
    --learning_rate=3e-4
    --grad_clip_thresh=4.0
    --num_steps=1200
    --report_interval=200
    --checkpoint_interval=20000
)
```

To launch your training, run your sbatch script,

```
sbatch 1.train.sbatch
```

You'll find a new file in the FSDP directory of the form `slurm-[job-number].out`. This will be continuously updated with your training logs. Don't be worried if you see a long stream of NCCL logs (we prefer to use `NCCL_DEBUG=INFO` for verbose logging). After about a minute, you should see your model training, with an output similar to below.

```
+ GPUS_PER_NODE=8
+ export FI_EFA_USE_DEVICE_RDMA=1
+ FI_EFA_USE_DEVICE_RDMA=1
+ export FI_EFA_FORK_SAFE=1
+ FI_EFA_FORK_SAFE=1
+ export FI_LOG_LEVEL=1
+ FI_LOG_LEVEL=1
+ export FI_PROVIDER=efa
+ FI_PROVIDER=efa
+ export NCCL_DEBUG=INFO
+ NCCL_DEBUG=INFO
++ pwd
+ : /fsx/awsome-distributed-training/3.test_cases/20.FSDP-Mamba/mamba-train.sqsh
+ : /fsx
+ : /fsx:/fsx
+ ENROOT_ARGS=(--container-image $IMAGE --container-mount-home --container-mounts $FSX_MOUNT)
+ declare -a ENROOT_ARGS
+ TORCHRUN_ARGS=(--nproc_per_node=$GPUS_PER_NODE --nnodes=$SLURM_JOB_NUM_NODES --rdzv_id=$SLURM_JOB_ID --rdzv_backend=c10d --rdzv_endpoint=$(hostname))
++ hostname
+ declare -a TORCHRUN_ARGS
+ export TRAIN_SCRIPT=training.py
+ TRAIN_SCRIPT=training.py
+ MODEL_ARGS=(--ckpt_load_path=/fsx/mamba/pretrain/ckpt --ckpt_save_path=/fsx/mamba/pretrain/ckpt --model_name=llama2_13b --dataset_path=/fsx/data/examples_datasets/wikicorpus_llama2_7B_tokenized_4k --select$
+ declare -a MODEL_ARGS
+ srun -l /fsx/nsight-efa/target-linux-x64/nsys profile --sample none --delay 30 --duration 1200 --force-overwrite true --output '/fsx/nsys_profiles/report_llama2_job%q{SLURM_JOB_ID}_rank%q{SLURM_PROCID}_on_%q$
0: master_addr is only used for static rdzv_backend and when rdzv_endpoint is not specified.
0: WARNING:torch.distributed.run:
0: *****************************************
0: Setting OMP_NUM_THREADS environment variable for each process to be 1 in default, to avoid your system being overloaded, please further tune the variable for optimal performance in your application as neede$
0: *****************************************
1: master_addr is only used for static rdzv_backend and when rdzv_endpoint is not specified.
1: WARNING:torch.distributed.run:
1: *****************************************
1: Setting OMP_NUM_THREADS environment variable for each process to be 1 in default, to avoid your system being overloaded, please further tune the variable for optimal performance in your application as neede$
1: *****************************************
0: Key: model_name, Value: llama2_13b
```

If you need to cancel or modify your job, see the Slurm commands available in the [Slurm documentation](https://slurm.schedmd.com/quickstart.html).

## Known Issues

- Mamba requires `mamba-ssm` and  `causal-conv1d`. We experienced compatbility issues with latest version of torch and therefore the container uses torch 2.2 along with causal-conv1d version `1.2.0.post1` to avoid these isues.
- `mamba-ssm` uses `triton` for some of its operations. In a multi-node setting, we encountered issues with Triton when using the cache. This required a change to triton cache. (See ref: https://github.com/openai/triton/issues/2688). The container build therefore builds triton from source and makes the following changes to triton cache:

    `.env/lib/python3.10/site-packages/triton/runtime/cache.py:L7`
    ```diff
    + import torch.distributed as torch_distributed
    ```

    `.env/lib/python3.10/site-packages/triton/runtime/cache.py:L91`

    ```diff
    -    temp_path = f"{filepath}.tmp.pid_{pid}_{rnd_id}"
    -    mode = "wb" if binary else "w"
    -    with open(temp_path, mode) as f:
    -        f.write(data)
    -    # Replace is guaranteed to be atomic on POSIX systems if it succeeds
    -    # so filepath cannot see a partial write
    -    os.replace(temp_path, filepath)
    +    # *** Rank 0 only ***
    +    if torch_distributed.is_initialized() and torch_distributed.get_rank() == 0:
    +        temp_path = f"{filepath}.tmp.pid_{pid}_{rnd_id}"
    +        mode = "wb" if binary else "w"
    +        with open(temp_path, mode) as f:
    +            f.write(data)
    +        # Replace is guaranteed to be atomic on POSIX systems if it succeeds
    +        # so filepath cannot see a partial write
    +        os.replace(temp_path, filepath)
    +    elif not torch_distributed.is_initialized():
    +        temp_path = f"{filepath}.tmp.pid_{pid}_{rnd_id}"
    +        mode = "wb" if binary else "w"
    +        with open(temp_path, mode) as f:
    +            f.write(data)
    +        # Replace is guaranteed to be atomic on POSIX systems if it succeeds
    +        # so filepath cannot see a partial write
    +        os.replace(temp_path, filepath)

    +    # *** Add a distributed barrier ***
    +    if torch_distributed.is_initialized():
    +        torch_distributed.barrier()
    ```