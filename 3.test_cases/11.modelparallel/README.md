## Using SageMaker Model Parallelism with Simple Llama 2 Training Job
The Amazon SageMaker model parallelism library (SMP) is a capability of SageMaker that enables high performance and optimized large scale training on SageMaker accelerate compute instances. Its core features include techniques and optimizations to accelerate and simplify large model training, such as hybrid sharded data parallelism, tensor parallelism, activation checkpointing, and activation offloading. You can use SMP to accelerate the training and fine-tuning of large language models (LLMs), large vision models (LVMs), and foundation models (FMs) with hundreds of billions of parameters.

The latest release of Amazon SageMaker model parallelism (SMP v2) aligns the library’s APIs and methods with open source PyTorch Fully Sharded Data Parallelism (FSDP), allowing users to easily enable SMP’s performance optimizations with minimal code change. Now, you can achieve state-of-the-art large model training performance on SageMaker in minutes by migrating your existing FSDP training scripts to SMP.

In this directory, we have example scripts for training with SMP Pytorch. We assume you have already setup a Hyperpod instance. Below we first describe the files in this directory, and then go over how to run some jobs.

### Files
- `train_lib.py` : Main training script
- `train.py` : Entrypoint to launch `train_lib.py`
- `scripts/model.sh` : Main script which passes the config and launches `train.py`. This is used by `conda_launch.sh` and scripts in convergence_jobs folder. If you want to define your own model configuration you might want to modify this.
- `arguments.py` : Parses arguments for the job. Please refer to this file for all the options the script supports.
- `checkpoints.py` : Handles saving and loading of checkpoints
- `data/pipelines/data_pipeline.py`: Creates dataloaders for the job. Modify this file to load your own dataset.
-  `data/utils.py`, `fsdp_utils.py`, `learning_rates.py`, `logging_utils.py`, `memory_tracker.py`, `train_utils.py` have utilities used by the main script.

#### Launch scripts
- `conda_launch.sh` : This is a slurm script which launches a job using the activated conda environment. It expects to be run on the head node of the Slurm cluster. See below section for instructions. By default it runs with synthetic data to make it easy to test the scripts.

## Note on paths
These scripts need to be put on a directory that can be accessed on all nodes, such as FSX.
We also recommend setting all paths (for input data and checkpoints) as shared directories using FSX.

### cuDNN Download for cuda11.8 and cuda12.1
We recommend that you install cuDNN for your desired cuda version using from the NVIDIA Developer page: https://developer.nvidia.com/cudnn. Once you visit the link you will need to:
1. Make a developer account.
2. Click on "Download cuDNN Library".
3. Agree to the terms.
4. Download the Local Installer for Linux x86_64 (Tar) for cuda11 or cuda12 (we recommend version 8.9.5 and will use that version in the example going forward).
4. Sync it with your cluster to the root directory. 

Once you have the tar file downloaded you can run the following commands to finish the installation:

### Conda Environment Setup
All commands below should be run on a compute node. You can run it as a script using ```awsome-distributed-training/3.test_cases/11.modelparallel/conda_env_setup.sh``` or manually run the script as individual commands which are listed below. Also, the cuda version should be decided here between versions 11.8 and 12.1. We recommend using Miniconda or Mamba and installing it in `/fsx` so that it can be sourced on any node. Instructions here: https://docs.conda.io/projects/conda/en/latest/user-guide/install/linux.html

```
# specify which CUDA version you are using
SMP_CUDA_VER=11.8 #or 12.1

source /fsx/<path to miniconda>/miniconda3/bin/activate

export ENV_PATH=/fsx/<path to miniconda>/miniconda3/envs/<env name>
conda create -p ${ENV_PATH} python=3.10

conda activate ${ENV_PATH}

# Install aws-cli if not already installed
# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#cliv2-linux-install

aws s3 sync s3://sagemaker-distributed-model-parallel/smp-2.0.0-pt-2.0.1/2023-12-11/smp-v2/ /tmp/local_smp_install_channel/

conda install pytorch="2.0.1=sm_py3.10_cuda${SMP_CUDA_VER}*" packaging --override-channels \
  -c file:///tmp/local_smp_install_channel/ \
  -c pytorch -c numba/label/dev \
  -c pytorch-nightly -c nvidia -c conda-forge

# Install dependencies of the script as below
python -m pip install packaging transformers==4.31.0 accelerate ninja tensorboard h5py datasets \
    && python -m pip install expecttest hypothesis \
    && python -m pip install "flash-attn>=2.0.4" --no-build-isolation

# Install SMDDP wheel (only run for cuda11.8)
SMDDP_WHL="smdistributed_dataparallel-2.0.2-cp310-cp310-linux_x86_64.whl" \
  && wget -q https://smdataparallel.s3.amazonaws.com/binary/pytorch/2.0.1/cu118/2023-12-07/${SMDDP_WHL} \
  && pip install --force ${SMDDP_WHL} \
  && rm ${SMDDP_WHL}

if [ $SMP_CUDA_VER == "11.8" ]; then
    # cuDNN installation for TransformerEngine installation for cuda11.8
    tar xf cudnn-linux-x86_64-8.9.5.30_cuda11-archive.tar.xz \
        && rm -rf /usr/local/cuda-$SMP_CUDA_VER/include/cudnn* /usr/local/cuda-$SMP_CUDA_VER/lib/cudnn* \
        && cp ./cudnn-linux-x86_64-8.9.5.30_cuda11-archive/include/* /usr/local/cuda-$SMP_CUDA_VER/include/ \
        && cp ./cudnn-linux-x86_64-8.9.5.30_cuda11-archive/lib/* /usr/local/cuda-$SMP_CUDA_VER/lib/ \
        && rm -rf cudnn-linux-x86_64-8.9.5.30_cuda11-archive.tar.xz \
        && rm -rf cudnn-linux-x86_64-8.9.5.30_cuda11-archive/
else
    # cuDNN installation for TransformerEngine installation for cuda12.1
    tar xf cudnn-linux-x86_64-8.9.7.29_cuda12-archive.tar.xz \
        && rm -rf /usr/local/cuda-$SMP_CUDA_VER/include/cudnn* /usr/local/cuda-$SMP_CUDA_VER/lib/cudnn* \
        && cp ./cudnn-linux-x86_64-8.9.7.29_cuda12-archive/include/* /usr/local/cuda-$SMP_CUDA_VER/include/ \
        && cp ./cudnn-linux-x86_64-8.9.7.29_cuda12-archive/lib/* /usr/local/cuda-$SMP_CUDA_VER/lib/ \
        && rm -rf cudnn-linux-x86_64-8.9.7.29_cuda12-archive.tar.xz \
        && rm -rf cudnn-linux-x86_64-8.9.7.29_cuda12-archive/
fi

# TransformerEngine installation
export CUDA_HOME=/usr/local/cuda-$SMP_CUDA_VER
export CUDNN_PATH=/usr/local/cuda-$SMP_CUDA_VER/lib
export CUDNN_LIBRARY=/usr/local/cuda-$SMP_CUDA_VER/lib
export CUDNN_INCLUDE_DIR=/usr/local/cuda-$SMP_CUDA_VER/include
export PATH=/usr/local/cuda-$SMP_CUDA_VER/bin:$PATH
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda-$SMP_CUDA_VER/lib

pip install --no-build-isolation git+https://github.com/NVIDIA/TransformerEngine.git@v1.0
```

## User Guide
1. **Launching a job with synthetic data on 16 nodes**

The default config in the script launches a 7B GPT NeoX model with synthetic data.
```
source /fsx/PATH/TO/CONDA/bin/activate
conda activate /PATH/TO/CONDA/ENV
sbatch -N 16 conda_launch.sh
```

2. **Changing arguments taken by the script**

`model.sh` takes certain arguments from the launch script, and uses them to pass args to the training script. You can refer to `model.sh` if those are the arguments you would like to change. For example, it takes the model size and sets the appropriate hidden_width,num_layers etc for the training script.

If model.sh doesn't take the argument but is taken by train_lib (arguments.py), you can still pass it to model.sh and the script will forward the arg. This is how the above script passes `--use_synthetic_data 1`.

3. **To run with your own data**

With the current dataloader in the script data needs to be prepared as json or json.gz (needs the arg  `--zipped_data 1`) files, where each file has a json line with input_ids and attention_mask in them. Please refer to data_pipeline.py for more. You can always replace with your own dataloader.
```
# 2a. modify the conda_launch.sh script with path to data
# 2b. start training
sbatch -N 16 conda_launch.sh /PATH/TO/CONDA/ENV
```

4. **Running a convergence job or experiment**

We have put together an example of a convergence script using the above referenced `scripts/model.sh` script. The script sets the model type, size, checkpointing directory, tensorboard directory for metrics, and other hyperparameters. This is a slurm script, used with sbatch similar to above.  Note that you will need to provide your own path to your dataset within the launch script below.

```
sbatch -N 16 convergence_jobs/neox_7b/neox_7b_4Mtokens.sh
```
or
```
sbatch -N 16 --job-name neox_7b_4M_trial1 convergence_jobs/neox_7b/neox_7b_4Mtokens.sh
```

5. **Resuming convergence job from a checkpoint**

Modify the `--resume_from_checkpoint` arg with the path of the checkpoint. Then the job is started same as before.
```
sbatch -N 16 convergence_jobs/neox_7b/neox_7b_4Mtokens.sh
```

6. **Running a finetuning job or experiment**

In order to run a finetune experiment `--finetune 1` needs to be set. Either pretrained model name `--pretrained_model_name` arg or a checkpoint file name `--pretrained_checkpoint_file` arg needs to be provided.

If `--pretrained_model_name` is provided pretrained model config will be used for finetuning. If `--pretrained_model_name` is provided `--finetune_checkpoint_load_dir` also needs to be provided.

If `--finetune 1`  is set together with `--resume_from_checkpoint`, training will resume from the provided checkpoint.
