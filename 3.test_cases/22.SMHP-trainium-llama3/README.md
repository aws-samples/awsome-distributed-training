# How to pre-train Llama3 with SageMaker Hyperpod using Amazon Trainium

## What is SageMaker Hyperpod?
[Amazon SageMaker Hyperpod](https://aws.amazon.com/sagemaker/hyperpod/) offers advanced training tools to help you accelerate scalable, reliable, and secure generative AI application development. It removes the undifferentiated heavy lifting involved in building and optimizing machine learning (ML) infrastructure for training foundation models (FMs) significantly reducing training time. SageMaker Hyperpod ensure customers can continue FM training uninterrupted by periodically saving checkpoints. When a hardware failure occurs during training, SageMaker Hyperpod automatically detects the failure, repairs, or replaces the faulty instance, and resumes the training from the last saved checkpoint, removing the need for customers to manually manage this process and helping them train for week or months in a distributed setting without disruption. 

SageMaker Hyperpod also allows customers to run their FM training workloads on [AWS Trainium](https://aws.amazon.com/machine-learning/trainium/). AWS Trainium is the machine learning (ML) chip that AWS purpose built for deep learning (DL) training of 100B+ parameter models. Each Amazon Elastic Compute Cloud (Amazon EC2) [Trn1 instance](https://aws.amazon.com/ec2/instance-types/trn1) deploys up to 16 Trainium accelerators to deliver a high-performance, low-cost solution for DL training in the cloud. [AWS Neuron SDK](https://aws.amazon.com/machine-learning/neuron/) helps developers train models on Trainium accelerators (and deploy them on [AWS Inferentia](https://aws.amazon.com/machine-learning/inferentia/) accelerators). It natively integrates popular frameworks, such as PyTorch and Tensorflow, so that you can continue to train on Trainium accelerators and use your existing code and workflows.

## 0. Prerequisites
You will need to set up a SageMaker Hyperpod cluster using 16 [trn1.32xlarge](https://aws.amazon.com/ec2/instance-types/trn1/) instances with a shared parallel filesystem such as [Amazon FSx for Lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/getting-started.html).  See the sagemaker-hyperpod section in the [Sagemaker Hyperpod](https://github.com/aws-samples/awsome-distributed-training/tree/main/1.architectures/5.sagemaker-hyperpod) folder for setup instructions.  

## 1. Create Environment 

1. Once the cluster is set up, SSH into the cluster head/controller node and switch to the `ubuntu` user:
``` bash
sudo su - ubuntu
```
> [!NOTE]  
> You will run the following steps from the head/controller node of your cluster.

2. Make sure the home directory is set up to `/fsx/ubuntu` as this will allow us to install the required dependencies only once on the head node:

``` bash
pwd
```

3. Next install Python virtual environment:

``` bash
# Install Python venv 
sudo apt-get install -y python3.8-venv g++ 

# Create Python venv
python3.8 -m venv /fsx/ubuntu/aws_neuron_venv_pytorch

```

Now lets activate the Virtual Environment:
```bash
# Activate Python venv 
source /fsx/ubuntu/aws_neuron_venv_pytorch/bin/activate 
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
python -m pip install torch-neuronx=="2.1.2.2.2.0" neuronx-cc=="2.14.213.0" neuronx_distributed=="0.8.0" torchvision
```

In this last step of this section, we will fetch llama3 test case from `neuronx-distributed`. The test case is included in the official repository, so first clone the repository under home directory.

```bash
git clone https://github.com/aws-neuron/neuronx-distributed.git \
          /fsx/ubuntu/neuronx-distributed
```

then copy the llama3 test case under home directory, then move to the directory:

```bash
cp -r /fsx/ubuntu/neuronx-distributed/examples/training/llama /fsx/ubuntu/llama
cp /fsx/ubuntu/neuronx-distributed/examples/training/checkpoint_converter.py /fsx/ubuntu/llama
cd /fsx/ubuntu/llama
```

finally, install additional dependencies using pip:

```bash
source /fsx/ubuntu/aws_neuron_venv_pytorch/bin/activate
pip install -r requirements.txt
```

## 2. Prepare Dataset

Next, we need to download and tokenize our dataset. To tokenize the data, you must request the tokenizer from HuggingFace and Meta by following the instructions at the following link: [HuggingFace Llama 3 70B Model](https://huggingface.co/meta-llama/Meta-Llama-3-70B) . Use of the Llama 3 model is governed by the Meta license. In order to download the model weights and tokenizer, please visit the above website and accept their License before requesting access. After access has been granted, you may use the download scripts provided by Meta to download the model weights and tokenizer to your cluster.

1. Install the huggingface CLI and download the model:

```bash
pip install huggingface-hub 
```

2. Authenticate with your [HuggingFace Access Token](https://huggingface.co/settings/tokens). 
> [!IMPORTANT]  
> Ensure your HuggingFace Access Token has permissions to public gated repos. You can configure your token to access public gated repos with: (*Edit Acces Token Permissions* > Check the Box: *Read access to contents of all public gated repos you can access* > Save).
```bash
huggingface-cli login
```
3. Download the [Meta-Llama-3-70B](https://huggingface.co/meta-llama/Meta-Llama-3-70B) repo from HuggingFace:

```bash
huggingface-cli download meta-llama/Meta-Llama-3-70B --local-dir /fsx/ubuntu/Meta-Llama-3-70B
```

Once the download process is completed, you will see the following structure:

```
/fsx/ubuntu/Meta-Llama-3-70B/
├── LICENSE
├── README.md
├── USE_POLICY.md
├── config.json
├── generation_config.json
├── model-00001-of-00030.safetensors
...
├── model-00030-of-00030.safetensors
├── model.safetensors.index.json
├── original
│   ├── consolidated.00.pth
....
│   ├── consolidated.07.pth
│   ├── params.json
│   └── tokenizer.model
├── special_tokens_map.json
├── tokenizer.json
└── tokenizer_config.json
```

Copy tokenizer configs under the test case repository.

```
cp /fsx/Meta-Llama-3-70B/tokenizer* /fsx/ubuntu/llama
```

4. Next, we will download wiki-corpus dataset and tokenize it for later training with get_dataset.py script inside the llama directory. We use sbatch  command to submit the data processing job to the cluster:

```bash
sbatch --job-name=get_dataset --output=logs/get_dataset.out \
       --wrap="srun python get_dataset.py"
```

It will creates a job named `get_dataset` and dump outputs into `logs/get_dataset.out`. You can track the progress with the following commant:

```bash
tail -f logs/get_dataset.out 
```

The example output as follows:

```
Downloading data: 100%|██████████| 1.35G/1.35G [02:49<00:00, 7.94MB/s] 
Generating train split: 100%|██████████| 1359146/1359146 [01:11<00:00, 19139.43 examples/s]
Running tokenizer on dataset: 100%|██████████| 1359146/1359146 [07:13<00:00, 3132.18 examples/s]
Grouping texts in chunks of 8192: 100%|██████████| 1359146/1359146 [10:19<00:00, 2194.09 examples/s]
94025
Saving the dataset (21/21 shards): 100%|██████████| 94025/94025 [00:18<00:00, 5139.19 examples/s]
```

and resultant data will be saved under examples_datasets directory.

```
/fsx/ubuntu/examples_datasets/wikicorpus_llama3_tokenized_8k/
├── data-00000-of-00021.arrow
...
├── data-00020-of-00021.arrow
├── dataset_info.json
└── state.json
```

## 3. Run continual pretraining job

In this last step, we will conduct Llama3 continual pretraining with Neuron Distributed using pretrained checkpoint downloaded in the previous step. 

1. Neuron Distributed requires its checkpoints to be pre-sharded based on the parallel processing configuration (tensor parallel degree and pipeline parallel degree). This preprocessing involves two main steps:

* Save original checkpoint into single binary file. This file will be used in the next step.
* Shard the checkpoints using the convert_checkpoints.py utility script.

First, we need to save the original checkpoint into a single binary file. Below is a small script named save-llama3-70B-model.py to accomplish this:

```bash
cat <<EOF > save-llama3-70B-model.py
from transformers import AutoTokenizer, AutoModelForCausalLM
import torch

model = AutoModelForCausalLM.from_pretrained("/fsx/Meta-Llama-3-70B")
torch.save(model.state_dict(), '/fsx/llama-3-70b.pt')
EOF
```

Submit the job with the following command to run the process on a compute node (trn1.32xlarge) which has sufficient memory to load the model:

```bash
sbatch --job-name=save-checkpoints --output=logs/save-checkpoints.out \
       --wrap "srun python save-llama3-70B-model.py"
```

Next, we use the convert_checkpoints.py script to shard the checkpoints. Execute the following command:

```bash
sbatch --job-name=convert-checkpoint --output=logs/convert-checkpoint.out \
       --wrap "\
              srun python3 convert_checkpoints.py \
              --tp_size 32 --pp_size 8 --n_layers 80 \
              --save_xser 1 \
              --kv_size_multiplier 4 \
              --qkv_linear 1 \
              --input_dir /fsx/ubuntu/llama-3-70b.pt \
              --output_dir /fsx/ubuntu/Llama-3-70B-nxd \
              --config /fsx/ubuntu/Meta-Llama-3-70B/config.json \
              --convert_from_full_state"
```

You can track the progress with

```bash
tail -f logs/convert-checkpoint.out
```

During the sharding process, you will see outputs like:

```
Saving to /fsx/ubuntu/Llama-3-70B-nxd/model/dp_rank_00_tp_rank_00_pp_rank_00.pt
Saving to /fsx/ubuntu/Llama-3-70B-nxd/model/dp_rank_00_tp_rank_00_pp_rank_01.pt
Saving to /fsx/ubuntu/Llama-3-70B-nxd/model/dp_rank_00_tp_rank_00_pp_rank_02.pt
Saving to /fsx/ubuntu/Llama-3-70B-nxd/model/dp_rank_00_tp_rank_00_pp_rank_03.pt
Saving to /fsx/ubuntu/Llama-3-70B-nxd/model/dp_rank_00_tp_rank_00_pp_rank_04.pt
Saving to /fsx/ubuntu/Llama-3-70B-nxd/model/dp_rank_00_tp_rank_00_pp_rank_05.pt
...
```

This process will shard the model per tensor parallel and pipeline parallel dimensions. In this case, we have `32x8=256` checkpoints.
Verify the number of checkpoints with:

```bash
ls /fsx/ubuntu/Llama-3-70B-nxd/model/ | wc -l
256
```

2. Now that we have preprocessed data and checkpoints and ready to submit continual pretraining job.  We have two subdirectories under `/fsx/ubuntu/llama`, `tp_pp_llama_hf_pretrain` and `tp_zero1_llama_hf_pretrain`. In this blog post, we use the former. Copy the relevant files into the current directory:

```bash
mv tp_pp_llama_hf_pretrain/* .
```

Notice that you have template scripts per model inside the directory, we will use `run_llama3_70B_tp_pp.sh`.

Contrary to the cluster setup, the script is assuming shared directory to be `/shared`. Modify them to `/fsx` as follows:

```bash
sed -i 's/\/shared/\/fsx\/ubuntu/g' run_llama3_70B_tp_pp.sh
```

Also, existing checkpoint loading does not included in the default `torchrun` arguments. Add the following to start training from checkpoint saved in `/fsx/ubuntu/Llama3-70B-nxd`:

```bash
torchrun $DISTRIBUTED_ARGS run_llama_nxd.py \
        ...
        --pretrained_weight_dir /fsx/ubuntu/Llama-3-70B-nxd/model \ # Add this
        ...
        --tb_dir $tb_dir |& tee $LOG_PATH/log
exit ${PIPESTATUS[0]}  
```

without this argument, pretraining process starts from scratch.
Finally, submit the training job as follows:

```bash
sbatch --auto-resume=True \
       --job-name run_llama3_70B \
       --output logs/run_llama3_70B.out \
       --exclusive --nodes 16 \
       --wrap="srun bash run_llama3_70B_tp_pp.sh"
```

You can track job progress as follows:

```bash
tail -f logs/run_llama3_70B.out
```







