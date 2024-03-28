## Using SageMaker Model Parallelism with Llama V2 Training Job

The Amazon SageMaker model parallelism library (SMP) is a capability of SageMaker that enables high performance and optimized large scale training on SageMaker accelerated compute instances. Its core features are hybrid sharded data parallelism, tensor parallelism, activation checkpointing, and activation offloading. You can use SMP to accelerate the training and fine-tuning of large language models (LLMs), large vision models (LVMs), and foundation models (FMs) with hundreds of billions of parameters such as [Llama2](https://huggingface.co/docs/transformers/model_doc/llama2) and [GPT-NeoX](https://huggingface.co/docs/transformers/model_doc/gpt_neox).

The latest release of Amazon SageMaker model parallelism (SMP v2) aligns the library’s APIs and methods with open source PyTorch Fully Sharded Data Parallelism ([FSDP](https://pytorch.org/docs/stable/fsdp.html)), allowing users to easily enable SMP’s performance optimizations with minimal code change. Now, you can achieve state-of-the-art large model training performance on SageMaker in minutes by migrating your existing FSDP training scripts to SMP. We added support for FP8 training for Llama2 and GPT-NeoX Hugging Face transformer models on P5 instances with Transformer Engine integration.

In this directory, we have example scripts for training with SMP Pytorch. We assume you have already setup a Hyperpod instance. Below we first describe the files in this directory, and then go over how to run some jobs.

### Files

All source files are located in the scripts directory

**Training Scripts**
- `train_lib.py` : Main training script
- `train_utils.py`: Implements several key functions in the central training script for model initialization, activation checkpointing, and more.

#### Launch Scripts
- `launch_training_enroot.sh`: Slurm sbatch script which launches a job using enroot. It should be run on head-node, and it uses synthetic data by default allowing training to be tested easily. If you want to define your own model configuration you might want to modify this file.

- `launch_training_conda.sh`: Slurm sbatch script which launches a job using conda environment. It should be run on head-node, and it uses synthetic data by default allowing training to be tested easily. If you want to define your own model configuration you might want to modify this file.

**Dataset and Dataloading Scripts**
- `data/pipelines/data_pipeline.py`: Creates dataloaders for the job. Modify this file to load your own dataset.
- `data/utils.py`: Utility file to facilitate using datasets stored in AWS S3.

**Miscellaneous Utility Scripts**
- `arguments.py`: Parses arguments for the job. Please refer to this file for all the options the script supports.
- `checkpoints.py`: Handles saving and loading of checkpoints
-  `learning_rates.py`: Utility file for implementing learning rate annealing during training
-  `logging_utils.py`: Implements several helper functions for logging key information during training such as loss, training throughput speeds, and environment variables
-  `memory_tracker.py`: Implements functions for monitoring CPU and GPU memory usage


#### The repository allows users to run training using either enroot pyxis or a conda environment chooose the option according to your requirement.

## Option 1 -  Run Training using Conda Environment

### Build conda environment

We have provided a setup script which installs the required libraries along with SMP V2 library. 

Make sure to use one of the worker nodes to run the script as the worker nodes have more vcpu's than the controller node.

```
bash setup_conda_env.sh
 ```

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



### User Guide
1. **Launching a job with synthetic data on 8 nodes**

The default config in the script launches a 70B Llama model with synthetic data.
```

sbatch launch_training_conda.sh
```

2. **Changing arguments taken by the script**

`launch_training_conda.sh` has certain arguments and uses them to pass args to the training script. You can refer to `launch_training_conda.sh` if those are the arguments you would like to change. For example, it takes the model size and sets the appropriate hidden_width,num_layers etc for the training script. If you are using P4 instance disable fp8 training by setting the ```--fp8``` parameter to 0.


3. **To run with your own data**

With the current dataloader in the script data can be either prepared as json or json.gz (needs the arg  `--zipped_data 1`) files, where each file has a json line with input_ids and attention_mask in them or we can use the huggingface format. Please refer to data_pipeline.py for more. You can always replace with your own dataloader.
```
# 2a. modify the launch_training_enroot.sh script with path to data
# 2b. start training
sbatch launch_training_conda.sh
```

4. **Resuming job from a checkpoint**

Modify the launch_training_conda.sh to add `--resume_from_checkpoint` arg to the srun command with the path of the checkpoint. Then the job is started same as before.
```
sbatch launch_training_conda.sh
```


## Option 2 -  Run Training using Docker and Enroot


### Prerequisities

1. In order to download SMP image from ECR we need to have below policy added to the role attached to HyperPod 

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:BatchCheckLayerAvailability",
                "ecr:BatchGetImage",
                "ecr-public:*",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetAuthorizationToken",
                "sts:*"
            ],
            "Resource": "*"
        }
    ]
}
```

### Build enroot sqsh file

We will build docker image extending SMPV2 image in ECR. To create the sqsh file run the docker_build.sh. 

Make sure to use one of the worker nodes to run the script as the worker nodes are configured to use NVME for docker/enroot cache. 

```
bash docker_build.sh
 ```

### User Guide
1. **Launching a job with synthetic data on 8 nodes**

The default config in the script launches a 70B Llama model with synthetic data.
```

sbatch launch_training_enroot.sh
```

2. **Changing arguments taken by the script**

`launch_training_enroot.sh` has certain arguments and uses them to pass args to the training script. You can refer to `launch_training_enroot.sh` if those are the arguments you would like to change. For example, it takes the model size and sets the appropriate hidden_width,num_layers etc for the training script. If you are using P4 instance disable fp8 training by setting the ```--fp8``` parameter to 0.


3. **To run with your own data**

With the current dataloader in the script data can be either prepared as json or json.gz (needs the arg  `--zipped_data 1`) files, where each file has a json line with input_ids and attention_mask in them or we can use the huggingface format. Please refer to data_pipeline.py for more. You can always replace with your own dataloader.
```
# 2a. modify the launch_training_enroot.sh script with path to data
# 2b. start training
sbatch launch_training_enroot.sh
```

4. **Resuming job from a checkpoint**

Modify the launch_training_enroot.sh to add `--resume_from_checkpoint` arg to the srun command with the path of the checkpoint. Then the job is started same as before.
```
sbatch launch_training_enroot.sh
```