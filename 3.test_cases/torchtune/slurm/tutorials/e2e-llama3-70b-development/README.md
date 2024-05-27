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

In this step, you will fine tune llama model with Low-Rank Adaptation (LoRA), using Alpaca dataset.  
Low-Rank Adaptation (LoRA) is a method introduced by Microsoft researchers in 2021 for fine-tuning large language models and other AI models efficiently. It is a Parameter-efficient Fine-tuning (PEFT) technique that modifies a small, low-rank subset of a model's parameters, significantly reducing the computational cost and time required for fine-tuning. LoRA operates on the principle that large models, despite their size, inherently possess a low-dimensional structure, allowing significant changes to be represented with fewer parameters. This method involves decomposing large weight matrices into smaller matrices, drastically reducing the number of trainable parameters and making the adaptation process faster and less resource-intensive. LoRA achieves high-quality fine-tuning results by adjusting all the model's parameters, albeit not as precisely when the rank is low, which is generally acceptable for most tasks. It leverages the concept of lower-rank matrices to efficiently train models, making it a cost-effective solution for fine-tuning large language models.

```yaml
model:
  _component_: torchtune.models.llama3.lora_llama3_70b
  lora_attn_modules: ['q_proj', 'k_proj', 'v_proj']
  apply_lora_to_mlp: False
  apply_lora_to_output: False
  lora_rank: 16
  lora_alpha: 32
```
For this particular example, we utilize alpaca_data.json. This JSON file comprises a list of dictionaries where each dictionary contains the following fields:
instruction: a string that describes the task the model should perform. Each of the 52,000 instructions is unique.
input: a string providing optional context or input for the task. For instance, if the instruction is "Summarize the following article," the input would be the article text. Approximately 40% of the examples include an input.
output: a string representing the response to the instruction as generated by the text-davinci-003 model.
```yaml
dataset:
  _component_: torchtune.datasets.alpaca_dataset
  train_on_input: True
```


```bash
sbatch tutorials/e2e-llama3-70b-development/lora_finetune_distributed.sbatch
```

Once the job has been completed, you will see following outputs in the log:


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

```bash
==> logs/convert-checkpoint_560.out <==
0: INFO:torchtune.utils.logging:Model checkpoint of size 4.97 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/hf_model_0024_0.pt
0: INFO:torchtune.utils.logging:Model checkpoint of size 4.66 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/hf_model_0025_0.pt
0: INFO:torchtune.utils.logging:Model checkpoint of size 4.66 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/hf_model_0026_0.pt
0: INFO:torchtune.utils.logging:Model checkpoint of size 4.66 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/hf_model_0027_0.pt
0: INFO:torchtune.utils.logging:Model checkpoint of size 5.00 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/hf_model_0028_0.pt
0: INFO:torchtune.utils.logging:Model checkpoint of size 4.97 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/hf_model_0029_0.pt
0: INFO:torchtune.utils.logging:Model checkpoint of size 2.10 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/hf_model_0030_0.pt
0: INFO:torchtune.utils.logging:Adapter checkpoint of size 0.09 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/adapter_0.pt
0: ^M1|3251|Loss: 1.5955958366394043: 100%|██████████| 3251/3251 [2:07:13<00:00,  2.35s/it]
```

checkpoints are saved as

```bash
$ ls /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/
adapter_0.pt        hf_model_0002_0.pt  hf_model_0005_0.pt  hf_model_0008_0.pt  hf_model_0011_0.pt  hf_model_0014_0.pt  hf_model_0017_0.pt  hf_model_0020_0.pt  hf_model_0023_0.pt  hf_model_0026_0.pt  hf_model_0029_0.pt
config.json         hf_model_0003_0.pt  hf_model_0006_0.pt  hf_model_0009_0.pt  hf_model_0012_0.pt  hf_model_0015_0.pt  hf_model_0018_0.pt  hf_model_0021_0.pt  hf_model_0024_0.pt  hf_model_0027_0.pt  hf_model_0030_0.pt
hf_model_0001_0.pt  hf_model_0004_0.pt  hf_model_0007_0.pt  hf_model_0010_0.pt  hf_model_0013_0.pt  hf_model_0016_0.pt  hf_model_0019_0.pt  hf_model_0022_0.pt  hf_model_0025_0.pt  hf_model_0028_0.pt
```

Notice that you have `adapter_0.pt`, which stores weighhs for the lora adapter.

## 5. Evaluate Llama3 model with lm-evaluation harness

In this last section, you will evaluate Llama models. It will make use of [lm-evaluation-harness](https://github.com/EleutherAI/lm-evaluation-harness). 

You can submit sample evaluation job by:

```bash
sbatch 5.evaluate.sbatch
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