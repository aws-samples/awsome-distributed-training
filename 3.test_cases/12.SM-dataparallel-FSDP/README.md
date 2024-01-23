# How to use SageMaker Distributed Data Parallel Library (SMDDP) with PyTorch FSDP

## What is SMDDP?
The [SMDDP](https://docs.aws.amazon.com/sagemaker/latest/dg/data-parallel.html) library provides fast GPU collective communication algorithms on [p4d.24xlarge](https://aws.amazon.com/ec2/instance-types/p4/)/p4de.24xlarge instance types and serves as a drop-in replacement for the Nvidia Collective Communications Library ([NCCL](https://developer.nvidia.com/nccl)).  Specifically, SMDDP implements an optimized AllGather communication routine, which is the main source of GPU communication overhead in sharded data parallel training jobs.  With just two lines of code change, you can enable the SMDDP Library's optimized AllGather algorithm in your [PyTorch FSDP](https://pytorch.org/tutorials/intermediate/FSDP_tutorial.html) training jobs and speed up training by up to 20% compared to NCCL!  This examples shows how you can use SMDDP when training the [Falcon](https://falconllm.tii.ae/falcon-models.html) model with FSDP. 

Enabling SMDDP in your FSDP script is seamless.  The only required changes are the following two lines:
1. Importing SMDDP: `import smdistributed.dataparallel.torch.torch_smddp`
2. Initializing process group with SMDDP backend: `torch.distributed.init_process_group(backend="smddp")` 

## 0. Prerequisites
You will need a Slurm cluster with a shared parallel filesystem such as [Amazon FSx for Lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/getting-started.html).  See the sagemaker-hyperpod section in the [Sagemaker Hyperpod](https://github.com/aws-samples/awsome-distributed-training/tree/main/1.architectures/5.sagemaker-hyperpod) folder for setup instructions.  The required dependencies to use SMDDP in this example are listed below.  Note that CUDA is already provided on HyperPod.

### Required Dependencies of SMDDP Library
* Python==3.10
* CUDA==11.8
* PyTorch==2.0.1

Additionally, SMDDP must be used on AWS P4d or P4de instances.  This example also uses [mamba](https://github.com/mamba-org/mamba) as a package manager.  Mamba is a drop-in replacement for [conda](https://conda.io/projects/conda/en/latest/index.html) and it is recommended over [Miniconda](https://docs.conda.io/projects/miniconda/en/latest/) or [Anaconda](https://www.anaconda.com/) with SMDDP (see [Known Issues](#4-known-issues) section for more details)

## 1. Create Environment 
On your cluster head node, navigate to your shared FSx filesystem, which should be located at `/fsx`, and clone this repo 
```
cd /fsx
git clone https://github.com/aws-samples/awsome-distributed-training/
cd awsome-distributed-training/3.test_cases/12.SM-dataparallel-FSDP
```
3. Run the `0.create_conda_env.sh` script.  This will install [Mamba](https://github.com/mamba-org/mamba) and create an environment called `smdataparallel`.   Since the environment is created on the shared FSx filesystem, all compute nodes will have access to it.  Activate this environment via `conda activate smdataparallel`.

## 2. Prepare Dataset
To run this example, we will use part of the [glue/sst2 dataset](https://huggingface.co/datasets/glue) from HuggingFace.  To download and prepare a subset of this dataset for our example, run `python prepare_dataset.py` 

## 3. Launch Training
To launch the distributed training job, run `sbatch 1.run_training.sbatch`.  By default the number of nodes in the job is 2, but this can be changed either by (i) editing the sbatch script to change the `#SBATCH --nodes=...` argument, or (ii) run `sbatch --nodes=... 1.run_training.sbatch` to override the number of nodes in the sbatch script.

Launching the job will create a log file in the current directory (`slurm-<job_id>`)  which you can tail (via `tail -f slurm-<job_id>`) to monitor the progress of the training job.    You can also see the underlying launch script in `exec_torchrun.sh` and the training script in `scripts/train.py`

This example only runs training for one iteration and exits immediately.  You should see output similar to below
```
  4%|▍         | 1/25 [00:04<01:43,  4.32s/it]
0: ******epoch=0: train_ppl=tensor(653844.6250, device='cuda:0') train_loss=tensor(13.3906, device='cuda:0')******
0it [00:00, ?it/s]
0: *******epoch=0: eval_ppl=tensor(nan, device='cuda:0') eval_loss=tensor(nan, device='cuda:0')*******
0: Training done!
```
## 4. Known Issues
Ensure that you are installing PyTorch via conda before pip installing SMDDP (i.e. install PyTorch through `conda install` before installing SMDDP in your environment).  Additionally, we suggest to use [Mamba](https://github.com/mamba-org/mamba) as your package manager rather than Miniconda or Anaconda.  Mamba is a drop-in replacement for conda with improvements in dependency resolution.

Not following these suggestions may result in the following error after importing SMDDP in your training script: ``version `GLIBCXX_3.4.30' not found``

