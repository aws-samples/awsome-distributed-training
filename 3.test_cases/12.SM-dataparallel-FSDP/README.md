# How to Use SageMaker Distributed Data Parallel Library (SMDDP) with PyTorch FSDP

## What is SMDDP?
The [SMDDP](https://docs.aws.amazon.com/sagemaker/latest/dg/data-parallel.html) library provides fast GPU collective communication algorithms on P4d/P4de instance types and serves as a drop-in replacement for the Nvidia Collective Communications Library ([NCCL](https://developer.nvidia.com/nccl)).  Specifically, SMDDP implements an optimized AllGather communication routine, which is the main source of GPU communication overhead in sharded data parallel training jobs.  With just two lines of code change, you can enable the SMDDP Library's optimized AllGather algorithm in your [PyTorch FSDP](https://pytorch.org/tutorials/intermediate/FSDP_tutorial.html) training jobs and speed up training by up to 20% compared to NCCL!  This examples shows how you can use SMDDP when training the [Falcon](https://falconllm.tii.ae/falcon-models.html) model with FSDP.  

## 0. Prerequisites
You will need a slurm cluster with a shared parallel filesystem such as [Amazon FSx for Lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/getting-started.html).  See the sagemaker-hyperpod section in the [1.architectures/5.sagemaker-hyperpod](https://github.com/aws-samples/awsome-distributed-training/tree/main/1.architectures/5.sagemaker-hyperpod) folder for setup instructions. 

### Required Dependencies of SMDDP Library
* Python==3.10
* CUDA==11.8
* PyTorch==2.0.1

Additionally, SMDDP must be used on AWS P4d or P4de instances.  This example also uses mamba as a package manager.  Mamba is a drop-in replacement for conda and it is recommended over Miniconda or Anaconda with SMDDP (see Known Issues section for more details)

## 1. Create Environment 
1. On your cluster head node, navigate to your shared FSx filesystem, which should be located at `/fsx`
2. Clone this repo 
```
cd /fsx
git clone https://github.com/aws-samples/awsome-distributed-training/
cd awsome-distributed-training/3.test_cases/12.SM-dataparallel-FSDP
```
3. Run the `0.create_conda_env.sh` script.  This will install [Mamba](https://github.com/mamba-org/mamba) and create an environment called `smdataparallel`.   Since the environment is created on the shared FSx filesystem, all compute nodes will have access to it.  Activate this environment via `conda activate smdataparallel`.

## 2. Prepare Dataset
To run this example, we will use part of the [glue/sst2 dataset](https://huggingface.co/datasets/glue) from HuggingFace.  To download and prepare a subset of this dataset for our example, run `./1.prepare_data.sh` 

## 3. Launch Training
To launch the distributed training job, run `sbatch 2.run_training.sbatch`.   By default the number of nodes in the job is 2, but this can be changed in the `#SBATCH --nodes=...` argument in the sbatch script.  

Launching the job will create a log file in the current directory (`slurm-<job_id>`)  which you can tail to monitor the progress of the training job.    You can also see the underlying launch script in `exec_torchrun.sh` and the training script in `scripts/train.py`

This example only runs training for one iteration and exits immediately.  You should see output similar to below
```
  4%|▍         | 1/25 [00:04<01:43,  4.32s/it]
0: ******epoch=0: train_ppl=tensor(653844.6250, device='cuda:0') train_loss=tensor(13.3906, device='cuda:0')******
0it [00:00, ?it/s]
0: *******epoch=0: eval_ppl=tensor(nan, device='cuda:0') eval_loss=tensor(nan, device='cuda:0')*******
0: Training done!
```
## 4. Known Issues
When using SMDDP in your own conda environment, you may encounter the following error after importing SMDDP in your training script: ``version `GLIBCXX_3.4.30' not found``

If this occurs, firstly ensure that you are installing PyTorch via conda before pip installing SMDDP (i.e. install PyTorch through `conda install` before installing SMDDP in your environment).  If this still does not resolve the error, please use [Mamba](https://github.com/mamba-org/mamba) as your package manager rather than Miniconda or Anaconda.  Mamba is a drop-in replacement for conda with improvements in dependency resolution, and creating an environment with Mamba is known to resolve this issue.

