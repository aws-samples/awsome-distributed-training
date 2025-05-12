## PEFT fine tuning of Llama 3 on Slurm cluster (trn1/trn1n)

This example showcases how to train llama 3 models using AWS Trainium instances and Huggingface Optimum Neuron. 🤗 Optimum Neuron is the interface between the 🤗 Transformers library and AWS Accelerators including AWS Trainium and AWS Inferentia. It provides a set of tools enabling easy model loading, training and inference on single- and multi-Accelerator settings for different downstream tasks.

### Solution overview
This solution uses the following components:

- AWS Trainium chips for deep learning acceleration
- Hugging Face Optimum-Neuron for integrating Trainium with existing models and tools
- LoRA for parameter-efficient fine tuning

## 0. Prerequisites

### 0.1 Cluster Setup
This guide assumes that you have following:
* Slurm cluster using 16 [trn1.32xlarge](https://aws.amazon.com/ec2/instance-types/trn1/) instances with a shared parallel filesystem such as [Amazon FSx for Lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/getting-started.html). 


The subsequent sections presume that you are operating from the home directory of this head node as the `ubuntu` user.


### 0.2 Setup Python Environment
Setup a virtual python environment and install your training dependencies. Make sure this repo is stored on the shared FSX volume of your cluster so all nodes have access to it.

```bash
chmod +x submit_jobs/0_create_env.sh
sbatch submit_jobs/0_create_env.sh
```

### Training

#### Step 1: Compile the model
Before you begin training on Trainium with Neuron, you will need to pre-compile your model with the neuron_parallel_compile CLI.  This will trace through the model's training code and apply optimizations to improve performance. 

```bash
chmod +x 2_compile_model.sh
sbatch 2_compile_model.sh
```
The compilation process will generate NEFF (Neuron Executable File Format) files that will speed up your model's fine tuning job.

#### Step 2: Fine Tuning
With your model compiled, you can now begin fine tuning your Llama 3 model. 

For the purposes of this workshop, we will use the dolly 15k dataset. As part of the training process, the script below will download the dataset and format it into a way that the model expects. Each data point will contain an instruction that guides the model's task, optional context that provides background information, and response that represent the desired output.

Now submit the fine tuning job:

```bash
chmod +x 3_finetune.sh
sbatch 3_finetune.sh
```

#### Step 3: Model Weight Consolidation
After training has completed, you will have a new directory for your model checkpoints. This directory will contain the model checkpoint shards from each neuron device that were generated during training. Use the model consolidation script to combine the shards into a single `model.safetensor` file.

```bash
chmod +x 4_model_consolidation.sh
sbatch 4_model_consolidation.sh
```
The `model.safetensor` file will contain the LoRA weights of your model that were updated during training.

#### Step 4: Merge Lora Weights
After consolidating the model shards, merge the LoRA adapter weights back to your base Llama 3 model:

```bash
chmod +x 5_merge_lora_weights.sh
sbatch 5_merge_lora_weights.sh
```
Your final fine tuned model weights will be saved to the `final_model_path` directory.

#### Step 5: Validate your trained model
Now that your model is fine tuned, see how its generations differ from the base model for the dolly-15k dataset.

```bash
chmod +x 6_inference.sh
sbatch 6_inference.sh
```
This will generate a prediction for the question "Who are you?", comparing the response of the base model to the fine tuned model. It will also pass a system prompt to the model to always respond like a pirate.

Before fine tuning:
```
{
    'role': 'assistant',
    'content': "Arrrr, me hearty! Me name be Captain Chat, the scurviest pirate chatbot to
    ever sail the Seven Seas! Me be here to regale ye with tales o' adventure, answer yer
    questions, and swab the decks o' yer doubts! So hoist the colors, me matey, and let's
    set sail fer a swashbucklin' good time!"
}
```
After fine tuning:
```
{
    'role': 'assistant',
    'content': "Arrr, shiver me timbers! Me be Captain Chat, the scurviest pirate chatbot to ever sail the Seven Seas! Me been programmin' me brain
    with the finest pirate lingo and booty-ful banter to make ye feel like ye just stumbled
   upon a chest overflowin' with golden doubloons! So hoist the colors, me hearty, and
    let's set sail fer a swashbucklin' good time!"
}
```

And that's it! You've successfully fine tuned a Llama 3 model on Amazon SageMaker HyperPod using PEFT with Neuron.