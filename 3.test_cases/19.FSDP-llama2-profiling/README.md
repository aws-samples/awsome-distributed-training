# Profiling Llama 2 (PyTorch FSDP) with PyTorch Profiler and NSight

These scripts provide an easy way to get started with multinode [FSDP](https://pytorch.org/tutorials/intermediate/FSDP_tutorial.html) training on Slurm. It provides examples on how to use PyTorch Profiler and Nvidia's NSight. PyTorch profiler helps with identifying time and memory costs of various PyTorch operations in your code. NVidia NSight, on the other hand, is a performance analysis tool designed to visualise application algorithms, identify opportunities for code optimization, and tune your code to scale across any quantity or size of GPUs and CPUs. 

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
cd awsome-distributed-training/3.test_cases/19.FSDP-llama2-profiling
```

3. Run the `0.create_conda_env.sh` script. 
* This script will first download and install [Miniconda](https://docs.conda.io/projects/miniconda/en/latest/), then create a Conda env called `llamapretrain`.

```
bash 0.create_conda_env.sh
```

* By creating this environment on the shared FSx for Lustre volume, all compute nodes in our cluster will have access to it.

## 2. Data

We can now download and tokenize our dataset. To tokenize the data, we must request tokenizer from 'HuggingFace and Meta' by following the instructions at the following link: [HuggingFace Llama2 7B model](https://huggingface.co/meta-llama/Llama-2-7b). In order to download the model weights and tokenizer, please visit the above website and accept their License before requesting access. After access has been granted, you may use the download scripts provided by Meta to download the model weights and tokenizer to your cluster.

Once you have downloaded the tokenizer and model weights, you can copy the tokenizer.model to the current working directory. 

Next run the following script to download and process the dataset:

```
   python3 get_dataset.py
```
We are now ready to start training.

## 3. Launch Training

We have the following scripts available to run Llama2 training:
1. `01.train.sbatch`: Runs Llama2 training with PyTorch profiler
2. `02.train_container.sbatch`: Runs Llama2 training with PyTorch profiler as a container workload using Enroot (See instructions on running training with Enroot below)
3. `03.nsys_train.sbatch`: Runs Llama2 traning with NSight profiling
4. `04.nsys_train_docker.sbatch`: Runs Llama2 training with NSight profiling as a container workload

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

If you are using non-EFA enabled instances, such as G4dn, or single GPU G5 nodes, comment out all EFA environment variables on lines 26-30.

Also, under `User Variables` make sure to adjust `GPUS_PER_NODE` to match the number of GPUs on your instance type (8 for P4d/P5, 4 for G5.12xlarge, 1 for G5.xlarge).

You can also adjust the training parameters in `MODEL_ARGS` (for example, to train Llama 2 70b, change --model_name to `llama2_70b`). Additional parameters can be found in `config/train_conf.py`. Note that we use the same directory for both ` --ckpt_load_path` and ` --ckpt_save_path`. If there are multiple checkpoints, ` --ckpt_load_path` will automatically select the most recent one. This way if our training is interupted for any reason, it will automatically pick up the most recent checkpoint.

```
declare -a MODEL_ARGS=(
    --model_name=llama2_7b
    --ckpt_load_path=/fsx/llama2/pretrain/ckpt
    --ckpt_save_path=/fsx/llama2/pretrain/ckpt
    --data_path=/fsx/data/
    --fsdp_activation_checkpointing=False
    --selective_checkpointing=1
    --sharding_strategy=hsdp
    --low_cpu_fsdp=False
    --batch_size=2
    --report_interval=200
    --checkpoint_interval=20000
    --use_torch_compile=False
    --use_profiler=True
)
```

To launch your training, run your preferred sbatch script, e.g.

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
+ : /fsx/fsdp-llama2-profile/awsome-distributed-training/3.test_cases/19.FSDP-llama2-profiling/fsdp-llama2-profiling.sqsh
+ : /fsx
+ : /fsx:/fsx
+ ENROOT_ARGS=(--container-image $IMAGE --container-mount-home --container-mounts $FSX_MOUNT)
+ declare -a ENROOT_ARGS
+ TORCHRUN_ARGS=(--nproc_per_node=$GPUS_PER_NODE --nnodes=$SLURM_JOB_NUM_NODES --rdzv_id=$SLURM_JOB_ID --rdzv_backend=c10d --rdzv_endpoint=$(hostname))
++ hostname
+ declare -a TORCHRUN_ARGS
+ export TRAIN_SCRIPT=training.py
+ TRAIN_SCRIPT=training.py
+ MODEL_ARGS=(--ckpt_load_path=/fsx/llama2/pretrain/ckpt --ckpt_save_path=/fsx/llama2/pretrain/ckpt --model_name=llama2_13b --dataset_path=/fsx/data/examples_datasets/wikicorpus_llama2_7B_tokenized_4k --select$
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

## 4. Build docker image
If you want to run the workload as a container, build the docker image and conver it to an Enroot squash file. To build the docker image run:

```
docker build -t ${DOCKER_IMAGE_NAME}:${TAG} .
```

## 5. Convert Docker image to Enroot
Convert the Docker container image to an [Enroot](https://github.com/NVIDIA/enroot) squash file. This step takes a few minutes.
```
enroot import -o fsdp-llama2.sqsh dockerd://${DOCKER_IMAGE_NAME}

```

Once the squash file has been generated, you can run `02.train_container.sbatch` or `04.nsys_train_docker.sbatch` scripts.