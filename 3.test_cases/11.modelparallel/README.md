## Using SageMaker Model Parallelism with Simple GPT-Neox Training Job
The Amazon SageMaker model parallelism library (SMP) is a capability of SageMaker that enables high performance and optimized large scale training on SageMaker accelerated compute instances. Its core features are hybrid sharded data parallelism, tensor parallelism, activation checkpointing, and activation offloading. You can use SMP to accelerate the training and fine-tuning of large language models (LLMs), large vision models (LVMs), and foundation models (FMs) with hundreds of billions of parameters such as [Llama2](https://huggingface.co/docs/transformers/model_doc/llama2) and [GPT-NeoX](https://huggingface.co/docs/transformers/model_doc/gpt_neox).

The latest release of Amazon SageMaker model parallelism (SMP v2) aligns the library’s APIs and methods with open source PyTorch Fully Sharded Data Parallelism ([FSDP](https://pytorch.org/docs/stable/fsdp.html)), allowing users to easily enable SMP’s performance optimizations with minimal code change. Now, you can achieve state-of-the-art large model training performance on SageMaker in minutes by migrating your existing FSDP training scripts to SMP.

In this directory, we have example scripts for training with SMP Pytorch. We assume you have already setup a Hyperpod instance. Below we first describe the files in this directory, and then go over how to run some jobs.

### Files
**Training Scripts**
- `train_lib.py` : Main training script
- `train_utils.py`: Implements several key functions in the central training script for model initialization, activation checkpointing, and more.

#### Launch Scripts
- `conda_launch.sh`: Slurm sbatch script which launches a job using the activated conda environment. It should be run on head-node, and it uses synthetic data by default allowing training to be tested easily.
-  `scripts/model.sh`: Main script which passes the config and launches training. This is used by `conda_launch.sh` and scripts in `convergence_jobs` folder. If you want to define your own model configuration you might want to modify this.

**Dataset and Dataloading Scripts**
- `data/pipelines/data_pipeline.py`: Creates dataloaders for the job. Modify this file to load your own dataset.
- `data/utils.py`: Utility file to facilitate using datasets stored in AWS S3.

**Miscellaneous Utility Scripts**
- `arguments.py`: Parses arguments for the job. Please refer to this file for all the options the script supports.
- `checkpoints.py`: Handles saving and loading of checkpoints
-  `learning_rates.py`: Utility file for implementing learning rate annealing during training
-  `logging_utils.py`: Implements several helper functions for logging key information during training such as loss, training throughput speeds, and environment variables
-  `memory_tracker.py`: Implements functions for monitoring CPU and GPU memory usage


## Note on paths
These scripts need to be put in a shared file system that can be accessed by all nodes, such as [FSx for Lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/what-is.html).
We also recommend setting all paths for input data and checkpoints as shared directories using FSx for Lustre.

### cuDNN Download for cuda11.8 and cuda12.1
We recommend that you install cuDNN for your desired cuda version using from the [NVIDIA Developer page](https://developer.nvidia.com/cudnn).  Click on the link and:
1. Make a developer account.
2. Click on "Download cuDNN Library".
3. Agree to the terms.
4. Download the Local Installer for Linux x86_64 (Tar) for cuda11 or cuda12 (we will use version 8.9.5 in the example going forward).
4. Move the tar file from your local machine to your cluster root directory. 

The next section will walk through how to finish the cuDNN installation.

### Conda Environment Setup
All commands below should be run on a compute node as some of the setup steps are compute intensive.  You can run it as a script using `conda_env_setup.sh` or manually run the script as individual commands which are listed below.  Also, the CUDA version should be decided here between versions 11.8 and 12.1. We recommend using Miniconda or Mamba and installing it on the shared file system, which in our example is FSx for Lustre   mounted at `/fsx`. Instructions for conda installation can be found [here](https://docs.conda.io/projects/conda/en/latest/user-guide/install/linux.html) 

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
