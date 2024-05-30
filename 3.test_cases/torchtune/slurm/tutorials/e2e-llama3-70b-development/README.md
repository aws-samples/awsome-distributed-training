# End-to-End LLama3-70B model development with Torchtune  <!-- omit in toc -->

In this tutorial, you will see how to:
* Pretrain
* Finetune
* Evaluate
* Deploy

## 1. Prerequisites
Before starting, ensure you have requested access to Meta-Llama-3-70B by visiting [Meta-Llama-3-70B](https://huggingface.co/meta-llama/Meta-Llama-3-70B) on Hugging Face and following the access request instructions. Additionally, make sure all prerequisites described in the [slurm](..) directory are set up.

## 2. Download llama3 model

To begin working with the Llama3-70B model, follow these steps to download the model weights and tokenizer:

### Setting Up Your Environment

Navigate to the [test case path](..) and prepare your environment by sourcing the `.env` file. This step is essential for setting up the paths and credentials needed to access and interact with the Llama3-70B model:

```bash
source .env
```

This step is crucial for configuring the necessary paths and credentials for accessing and working with the Llama3-70B model.

### Fetching the Model Weights and Tokenizer

Execute the `download_hf_model.sh` script with the model identifier as an argument to download the model weights and tokenizer:

```bash
bash download_hf_model.sh --model meta-llama/Meta-Llama-3-70B
```

Upon successful execution, the script will output messages indicating the progress of the download. Here's what you can expect to see:

```bash
Executing following command:
torchtune download --output-dir /fsx/ubuntu/models/torchtune/meta-llama/Meta-Llama-3-70B meta-llama/Meta-Llama-3-70B --ignore-patterns original/consolidated*

=============
== PyTorch ==
=============

NVIDIA Release 24.04 (build 88113656)
...
Downloading builder script: 100%|█████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████| 5.67k/5.67k [00:00<00:00, 29.6MB/s]
No CUDA runtime is found, using CUDA_HOME='/usr/local/cuda'
Ignoring files matching the following patterns: original/consolidated*
USE_POLICY.md: 100%|██████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████| 4.70k/4.70k [00:00<00:00, 16.3MB/s]
generation_config.json: 100%|█████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████| 177/177 [00:00<00:00, 1.96MB/s]
.gitattributes: 100%|█████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████| 1.52k/1.52k [00:00<00:00, 17.3MB/s]
README.md: 100%|███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████| 36.6k/36.6k [00:00<00:00, 181MB/s]
LICENSE: 100%|████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████| 7.80k/7.80k [00:00<00:00, 77.7MB/s]
...
/fsx/ubuntu/models/torchtune/meta-llama/Meta-Llama-3-70B/model-00007-of-00030.safetensors
/fsx/ubuntu/models/torchtune/meta-llama/Meta-Llama-3-70B/model-00016-of-00030.safetensors
/fsx/ubuntu/models/torchtune/meta-llama/Meta-Llama-3-70B/model-00010-of-00030.safetensors
/fsx/ubuntu/models/torchtune/meta-llama/Meta-Llama-3-70B/model-00001-of-00030.safetensors
/fsx/ubuntu/models/torchtune/meta-llama/Meta-Llama-3-70B/model-00028-of-00030.safetensors
/fsx/ubuntu/models/torchtune/meta-llama/Meta-Llama-3-70B/model-00023-of-00030.safetensors
```

This output confirms that the `torchtune download` command has been executed within the container, successfully downloading the safetensors for `meta-llama/Meta-Llama-3-70B` into the specified `${MODEL_PATH}`.
By following these steps, you ensure that the necessary model components are in place, setting the stage for subsequent tasks such as pretraining, finetuning, evaluation, and deployment.


## 3. Full-parameter finetuning

WIP In this step, you will author Llama3 model using c4 dataset. 

```bash
sbatch tutorials/e2e-llama3-70b-development/pretrain.sbatch
```


## 4. Lora parameter efficient finetuning

In this step, you will fine-tune the LLaMA model using Low-Rank Adaptation (LoRA) with the Alpaca dataset. We will first cover the basic concepts and relevant configurations found in the [config file](configs/lora_finetune_distributed.yaml), followed by a detailed fine-tuning tutorial.


### Basic Concepts and Relevant Configurations

**Low-Rank Adaptation (LoRA)** is a method for fine-tuning large language models efficiently. It is a Parameter-efficient Fine-tuning (PEFT) technique that modifies a small, low-rank subset of a model's parameters, significantly reducing the computational cost and time required for fine-tuning. LoRA operates on the principle that large models, despite their size, inherently possess a low-dimensional structure, allowing significant changes to be represented with fewer parameters. This method involves decomposing large weight matrices into smaller matrices, drastically reducing the number of trainable parameters and making the adaptation process faster and less resource-intensive. It leverages the concept of lower-rank matrices to efficiently train models, making it a cost-effective solution for fine-tuning large language models. 

In the config we have following relevant section:

```yaml
model:
  _component_: torchtune.models.llama3.lora_llama3_70b
  lora_attn_modules: ['q_proj', 'k_proj', 'v_proj']
  apply_lora_to_mlp: False
  apply_lora_to_output: False
  lora_rank: 16
  lora_alpha: 32
```
This config can be read as follows:

* This means that we only create LoRA adapters in attention heads, specifically for its Query, Key, and Value matrices.
* `lora_alpha` is a hyper-parameter to control the initialization scale.
* `lora_rank` is the rank of the LoRA parameters. The smaller the `lora_rank`, the fewer parameters LoRA has.

**The Stanford Alpaca dataset**  is a synthetic dataset created by Stanford researchers to fine-tune large language models (LLMs) for instruction-following tasks. It contains 52,000 unique instruction-output pairs generated using OpenAI's text-davinci-003 model. 

In the config we have the following relevant section:

```yaml
dataset:
  _component_: torchtune.datasets.alpaca_dataset
  train_on_input: True
```

As the config suggests, we use a predefined dataset class prepared in torchtune.

### Submit Finetuning job

You can submit the finetuning job with the following command:


```bash
sbatch tutorials/e2e-llama3-70b-development/lora_finetune_distributed.sbatch
```

Once the job has been scheduled, you will see following outputs in the log:


```bash
...
Executing following command:
torchtune run --master_addr 10.1.28.89 --master_port 14280 --nproc_per_node=8 --nnodes 1 --nnodes=1 --rdzv_backend=c10d --rdzv_endpoint=p5-st-p5-2 lora_finetune_distributed
...
0: wandb: Currently logged in as: <YOURUSERNAME>. Use `wandb login --relogin` to force relogin
0: wandb: Tracking run with wandb version 0.17.0
0: wandb: Run data is saved locally in /fsx/ubuntu/models/torchtune/meta-llama/Meta-Llama-3-70B-tuned/log/metrics/wandb/run-20240527_001350-oziekm6j
0: wandb: Run `wandb offline` to turn off syncing.
0: wandb: Syncing run helpful-surf-1
0: wandb: ⭐️ View project at https://wandb.ai/<YOURUSERNAME>/torchtune
0: wandb: 🚀 View run at https://wandb.ai/<YOURUSERNAME>/torchtune/runs/oziekm6j
0: 2024-05-27:00:13:50,919 INFO     [metric_logging.py:225] Logging /fsx/ubuntu/models/torchtune/meta-llama/Meta-Llama-3-70B/torchtune_config.yaml to W&B under Files
```

As the output indicates, we run a single-node distributed training job with 8 GPUs here.

```bash
torchtune run --master_addr 10.1.28.89 --master_port 14280 --nproc_per_node=8 --nnodes 1 --nnodes=1 --rdzv_backend=c10d --rdzv_endpoint=p5-st-p5-2 lora_finetune_distributed
```


After the training, checkpoints are saved as below:

```bash
$ ls /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/
adapter_0.pt        hf_model_0002_0.pt  hf_model_0005_0.pt  hf_model_0008_0.pt  hf_model_0011_0.pt  hf_model_0014_0.pt  hf_model_0017_0.pt  hf_model_0020_0.pt  hf_model_0023_0.pt  hf_model_0026_0.pt  hf_model_0029_0.pt
config.json         hf_model_0003_0.pt  hf_model_0006_0.pt  hf_model_0009_0.pt  hf_model_0012_0.pt  hf_model_0015_0.pt  hf_model_0018_0.pt  hf_model_0021_0.pt  hf_model_0024_0.pt  hf_model_0027_0.pt  hf_model_0030_0.pt
hf_model_0001_0.pt  hf_model_0004_0.pt  hf_model_0007_0.pt  hf_model_0010_0.pt  hf_model_0013_0.pt  hf_model_0016_0.pt  hf_model_0019_0.pt  hf_model_0022_0.pt  hf_model_0025_0.pt  hf_model_0028_0.pt
```

Notice that you have `adapter_0.pt`, which stores weighhs for the LoRA adapter.


## 5. Evaluate Llama3 model with lm-evaluation harness

In this last section, you will evaluate the finetuned Llama models. `torchtune` makes use of [lm-evaluation-harness](https://github.com/EleutherAI/lm-evaluation-harness) to conduct various benchmarks.

### Basic Concepts and Relevant Configurations

**The lm-evaluation-harness** is a tool designed to evaluate large language models (LLMs) on various natural language processing (NLP) tasks, ensuring objective and reproducible results. It supports multiple tasks, including text classification, question answering, and commonsense reasoning, allowing for comprehensive model evaluation. The tool provides detailed metrics such as F1-score, accuracy, balanced accuracy, and Matthews correlation coefficient (MCC) for specific tasks. Users can also evaluate models on custom datasets by setting up the environment and creating new task files. The primary goal is to standardize evaluations, making results comparable across different models and implementations. This is crucial for validating new techniques and approaches in LLM development. 

We specify evaluation task in the [config](./configs/evaluate_llama3.yaml) as below:

```yaml
# EleutherAI specific eval args
tasks: ["truthfulqa_mc2"]
```

In this default setting we will use TruthfulQA benchmark with MC2 mode.

**TruthfulQA** is a benchmark designed to evaluate the truthfulness of language models in generating answers to questions. It consists of 817 questions across 38 topics, including health, law, finance, and politics, specifically targeting common misconceptions that humans might incorrectly answer due to false beliefs or misinformation. TruthfulQA features two evaluation modes: MC1 and MC2. In MC2 (Multi-true), given a question and multiple true/false reference answers, the score is the normalized total probability assigned to the set of true answers. For more details, please refer to [the project repository](https://github.com/sylinrl/TruthfulQA).

You can submit sample evaluation job by:


```bash
sbatch evaluate.sbatch
```

You will see:

```
Running loglikelihood requests:   6%|▋         | 23/400 [00:01<00:18, 20.53it/s]
Running loglikelihood requests:  16%|█▌        | 62/400 [00:02<00:15, 22.65it/s]
Running loglikelihood requests:  24%|██▍       | 98/400 [00:04<00:13, 22.50it/s]
Running loglikelihood requests:  33%|███▎      | 131/400 [00:06<00:12, 22.28it/s]
Running loglikelihood requests:  42%|████▏     | 164/400 [00:07<00:10, 22.40it/s]
Running loglikelihood requests:  50%|█████     | 200/400 [00:09<00:08, 22.60it/s]
Running loglikelihood requests:  58%|█████▊    | 233/400 [00:10<00:07, 22.46it/s]
Running loglikelihood requests:  66%|██████▌   | 263/400 [00:11<00:06, 22.51it/s]
Running loglikelihood requests:  74%|███████▍  | 296/400 [00:13<00:04, 22.45it/s]
Running loglikelihood requests:  82%|█�██████▏ | 326/400 [00:14<00:03, 22.63it/s]/s]
Running loglikelihood requests:  90%|████████▉ | 356/400 [00:16<00:01, 22.82it/s]
Running loglikelihood requests:  97%|█████████▋| 389/400 [00:17<00:00, 23.11it/s]
Running loglikelihood requests: 100%|██████████| 400/400 [00:17<00:00, 22.27it/s]
0: fatal: not a git repository (or any of the parent directories): .git
0: 2024-05-07:01:12:39,479 INFO     [eval.py:69] vllm (pretrained=meta-llama/Meta-Llama-3-70B,tensor_parallel_size=8,dtype=auto,gpu_memory_utilization=0.8,data_parallel_size=1), gen_kwargs: (None), limit: 100.0, num_fewshot: None, batch_size: 1
0: 2024-05-07:01:12:39,536 INFO     [eval.py:70] |  Tasks  |Version|Filter|n-shot| Metric |Value|   |Stderr|
0: |---------|------:|------|-----:|--------|----:|---|-----:|
0: |hellaswag|      1|none  |     0|acc     | 0.56|±  |0.0499|
0: |         |       |none  |     0|acc_norm| 0.75|±  |0.0435|
0: 
```



## 5. Chat with Finetuned model

Now that you can test the finetuned-model deployment using vLLM. 

```bash
sbatch 7.generate.sbatch --config configs/generate_llama3.yaml --prompt "Hello, my name is"
```

```
[generate.py:122] Hello, my name is Sarah and I am a busy working mum of two young children, living in the North East of England.
...
[generate.py:135] Time for inference: 10.88 sec total, 18.94 tokens/sec
[generate.py:138] Bandwidth achieved: 346.09 GB/s
[generate.py:139] Memory used: 18.31 GB
```