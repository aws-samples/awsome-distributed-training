# LLaMA LoRA Model Fine-tuning and Inference

This project provides a set of scripts for fine-tuning a LLaMA model using LoRA (Low-Rank Adaptation), merging the fine-tuned model, and performing inference.

## Table of Contents
1. [Installation](#installation)
2. [Usage](#usage)
   - [Create the Environment](#create-the-environment-for-slurm)
   - [Downloading the Model](#downloading-the-model)
   - [Preparing the Dataset](#preparing-the-dataset)
   - [Setting Up and Training on a trn1.32xlarge Instance](#setting-up-and-training-on-a-trn132xlarge-instance)
     - [Pre-compile the Model](#pre-compile-the-model-for-optimized-neuron-training)
     - [Distributed Training](#distributed-training-with-torchrun)
   - [Post-Training Steps](#post-training-steps)
     - [Consolidating the Sharded Model](#consolidating-the-sharded-model)
     - [Merge the LoRA Weights](#merge-the-lora-weights)
     - [Run Inference Validation](#run-inference-validation)

## Installation

This project is set to run under slurm with a shared file system FSX claim attached to the cluster. You can download the folder under `/fsx/peft_optimum_neuron`.

## Usage

### Create the environment for slurm

```
sbatch 0_create_env.sh
```

### Downloading the Model

Use the `download_model.py` script to download the pre-trained model. Make sure you have a valid HuggingFace token exported in your current bash session/environment:

```
sbatch 1_download_model.sh
```

### Preparing the Dataset

Use the `prepare_dataset.py` script to prepare your dataset for training:

```
sbatch 2_download_model.sh
```

Arguments:
- `--model_name`: Name of the pre-trained model for tokenizer (default: "meta-llama/Meta-Llama-3.1-8B-Instruct")
- `--dataset_name`: Name of the dataset to use (default: "databricks/databricks-dolly-15k")
- `--block_size`: Maximum sequence length (default: 2048)
- `--seed`: Random seed (default: 42)
- `--output_dir`: Output directory for prepared datasets (default: "./prepared_dataset")

### Setting Up and Training on a trn1.32xlarge Instance

To leverage the full power of AWS Neuron for training, you can use a trn1.32xlarge instance. This instance type is optimized for machine learning workloads and provides significant computational resources.

1. Launch a trn1.32xlarge instance in your AWS account.
2. Connect to the instance using SSH.
3. Clone this repository and navigate to the project directory.
4. Install the required dependencies as described in the [Installation](#installation) section.

#### Pre-compile the model for optimized Neuron training

Compile the model with neuron_parallel_compile.

```bash
sbatch 2_compile_model.sh
```

#### Distributed Training with torchrun

For distributed training on a trn1.32xlarge instance, we use `torchrun` to manage the process. Here's how to run the training:

```bash
sbatch 3_finetune.sh
```
### Post-training steps

#### Consolidating the sharded model

Use the `model_consolidation.py` script to merge the LoRA weights with the base model and run inference:

```
sbatch 4_model_consolidation.sh
```

#### Merge the LoRA weights

```
sbatch 5_merge_lora_weights.sh
```

This script will merge the base model with the fine-tuned LoRA weights, run inference on a test set, and save the results to a JSON file.

#### Run inference validation

```
6_inference.sh
```
