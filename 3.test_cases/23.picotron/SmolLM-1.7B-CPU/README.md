# Running Small LLM with 3D Parallelism on Picotron 

This guide explains how to run distributed training using 3D parallelism with Picotron, using a 1.7B parameter LLaMA-based model as an example.

## What is 3D Parallelism?

3D parallelism combines three types of model parallelism to efficiently train large language models:

1. **Data Parallelism (DP)**: Splits training batches across multiple GPUs, with each GPU processing a subset of the data. This allows parallel processing of different batches to speed up training.

2. **Tensor Parallelism (TP)**: Splits individual tensors/layers across GPUs to distribute the model's parameters. This reduces memory requirements per device by partitioning large matrices.

3. **Pipeline Parallelism (PP)**: Splits the model vertically into stages that run on different GPUs in a pipelined fashion. This enables training of very deep models by distributing layers across devices.

This combination allows training of very large models that wouldn't fit on a single GPU while maintaining computational efficiency through balanced workload distribution and optimized communication patterns.

## Creating Training Configurations

The `create_config.py` script helps generate configuration files for different training scenarios. The script accepts various parameters to customize the training setup, including parallelism dimensions, model architecture, and training hyperparameters.

First, create a Hugging Face account to retrieve a [token](https://huggingface.co/settings/tokens.). Log in to your account and create an access token from Hugging Face Tokens. 

Save the token onto the head node and download the Llama model:

```bash
huggingface-cli login
```

You will be prompted to input the token. Paste the token and answer `n` when asked to add the token as a git credential.

```

    _|    _|  _|    _|    _|_|_|    _|_|_|  _|_|_|  _|      _|    _|_|_|      _|_|_|_|    _|_|      _|_|_|  _|_|_|_|
    _|    _|  _|    _|  _|        _|          _|    _|_|    _|  _|            _|        _|    _|  _|        _|
    _|_|_|_|  _|    _|  _|  _|_|  _|  _|_|    _|    _|  _|  _|  _|  _|_|      _|_|_|    _|_|_|_|  _|        _|_|_|
    _|    _|  _|    _|  _|    _|  _|    _|    _|    _|    _|_|  _|    _|      _|        _|    _|  _|        _|
    _|    _|    _|_|      _|_|_|    _|_|_|  _|_|_|  _|      _|    _|_|_|      _|        _|    _|    _|_|_|  _|_|_|_|

    To login, `huggingface_hub` requires a token generated from https://huggingface.co/settings/tokens .
Enter your token (input will not be visible): 
Add token as git credential? (Y/n) n
Token is valid (permission: read).
Your token has been saved to /fsx/ubuntu/.cache/huggingface/token
Login successful
```

Then use the saved token `${HF_TOKEN}` to create configuration.


```bash
# 3D Parallelism on CPU
python create_config.py --out_dir tmp --exp_name llama-1B-cpu --dp 2 --tp 2 --pp 2 
--pp_engine 1f1b --model_name HuggingFaceTB/SmolLM-1.7B --num_hidden_layers 5  
--grad_acc_steps 2 --mbs 4 --seq_len 128 --hf_token ${HF_TOKEN} --use_cpu
```



