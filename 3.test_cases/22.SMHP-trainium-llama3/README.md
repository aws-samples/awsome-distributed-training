# How to pre-train Llama3 with SageMaker Hyperpod using Amazon Trainium

## What is SageMaker Hyperpod?
[Amazon SageMaker Hyperpod](https://aws.amazon.com/sagemaker/hyperpod/) offers advanced training tools to help you accelerate scalable, reliable, and secure generative AI application development. It removes the undifferentiated heavy lifting involved in building and optimizing machine learning (ML) infrastructure for training foundation models (FMs) significantly reducing training time. SageMaker Hyperpod ensure customers can continue FM training uninterrupted by periodically saving checkpoints. When a hardware failure occurs during training, SageMaker Hyperpod automatically detects the failure, repairs, or replaces the faulty instance, and resumes the training from the last saved checkpoint, removing the need for customers to manually manage this process and helping them train for week or months in a distributed setting without disruption. 

SageMaker Hyperpod also allows customers to run their FM training workloads on [AWS Trainium](https://aws.amazon.com/machine-learning/trainium/). AWS Trainium is the machine learning (ML) chip that AWS purpose built for deep learning (DL) training of 100B+ parameter models. Each Amazon Elastic Compute Cloud (Amazon EC2) [Trn1 instance](https://aws.amazon.com/ec2/instance-types/trn1) deploys up to 16 Trainium accelerators to deliver a high-performance, low-cost solution for DL training in the cloud. [AWS Neuron SDK](https://aws.amazon.com/machine-learning/neuron/) helps developers train models on Trainium accelerators (and deploy them on [AWS Inferentia](https://aws.amazon.com/machine-learning/inferentia/) accelerators). It natively integrates popular frameworks, such as PyTorch and Tensorflow, so that you can continue to train on Trainium accelerators and use your existing code and workflows.

## 0. Prerequisites
You will need to set up a SageMaker Hyperpod cluster using 4 [trn1.32xlarge](https://aws.amazon.com/ec2/instance-types/trn1/) instances with a shared parallel filesystem such as [Amazon FSx for Lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/getting-started.html).  See the sagemaker-hyperpod section in the [Sagemaker Hyperpod](https://github.com/aws-samples/awsome-distributed-training/tree/main/1.architectures/5.sagemaker-hyperpod) folder for setup instructions.  

## 1. Create Environment 

1. Once the cluster is set up, SSH into the cluster and switch to the `ubuntu` user:
``` bash
sudo su - ubuntu
```

2. Make sure the home directory is set up to `/fsx/ubuntu` as this will allow us to install the required dependencies only once on the head node:

``` bash
pwd
```

3. Next install Python virtual environment:

``` bash
# Install Python venv 
sudo apt-get install -y python3.8-venv g++ 

# Create Python venv
python3.8 -m venv aws_neuron_venv_pytorch 

# Activate Python venv 
source aws_neuron_venv_pytorch/bin/activate 
python -m pip install -U pip 
```

4. Install PyTorch Neuron:

``` bash
# Install Jupyter notebook kernel
pip install ipykernel 
python3.8 -m ipykernel install --user --name aws_neuron_venv_pytorch --display-name "Python (torch-neuronx)"
pip install jupyter notebook
pip install environment_kernels

# Set pip repository pointing to the Neuron repository 
python -m pip config set global.extra-index-url https://pip.repos.neuron.amazonaws.com

# Install wget, awscli 
python -m pip install wget 
python -m pip install awscli 

# Install Neuron Compiler and Framework
python -m pip install neuronx-cc==2.* torch-neuronx torchvision
python -m pip install neuronx_distributed --extra-index-url https://pip.repos.neuron.amazonaws.com
```

On your cluster head node, clone this repo 
``` bash
git clone https://github.com/aws-samples/awsome-distributed-training/
cd awsome-distributed-training/3.test_cases/22.SMHP-trainium-llama3
```

## 2. Prepare Dataset

Next, we need to tokenize our dataset. To tokenize the data, you must request the tokenizer from HuggingFace and Meta by following the instructions at the following link: [HuggingFace Llama 3 8B Model](https://huggingface.co/meta-llama/Meta-Llama-3-8B) . Use of the Llama 3 model is governed by the Meta license. In order to download the model weights and tokenizer, please visit the above website and accept their License before requesting access. After access has been granted, you may use the download scripts provided by Meta to download the model weights and tokenizer to your cluster.

Once you have downloaded the tokenizer and model weights, you can copy the tokenizer.model, config.json and tokenizer.json files from the Llama 3 repo to the working directory (22.SMHP-trainium-llama3)

Run the 'get_dataset.py' script to prepare the dataset for training:

``` bash
python3 get_dataset.py
```

## 3. Compile Model

Next, we will comiplie the model graph using the [neuron parallel compile](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/frameworks/torch/torch-neuronx/api-reference-guide/training/pytorch-neuron-parallel-compile.html#pytorch-neuronx-parallel-compile-cli) tool. 

``` bash
sbatch --exclusive \ 
--nodes 4 \
--cpus-per-task 64 \
--wrap="srun neuron_parallel_compile bash $(pwd)/run_llama_8B_tp_pp.sh"
```

## 4. Run Training

Once the graphs are compiled, we can now run model training

``` bash
sbatch --exclusive \
--nodes 4 \
--cpus-per-task 64 \
--wrap="srun bash $(pwd)/run_llama_8B_tp_pp.sh"
```


