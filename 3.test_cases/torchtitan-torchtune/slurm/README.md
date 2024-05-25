# End-to-End LLM Model Development with Torchtitan and Torchtune on Slurm <!-- omit in toc -->

This example will go through how to
* Pretrain Llama3 model using `torchtitan`
* Finetune Llama3 model using `torchtune`
* Model evaluation with `lm-evaluation-harness` with `torchtune`
* Test model deployment with `vLLM`

on Slurm. 

## 1. Preparation

This guide assumes that you have the following:

* A functional Slurm cluster on AWS.
* Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
* An FSx for Lustre filesystem mounted on `/fsx`.

We recommend that you set up a Slurm cluster using the templates in the architectures [directory](../../../1.architectures). You need to set the following environment variables to run this test case.

To effectively monitor the model training process and computational resource usage, we will employ [Weights & Biases](https://wandb.ai/). You will need to create an account and obtain your `WANDB_API_KEY` from Weights & Biases [Settings](https://wandb.ai/settings). For detailed setup instructions, please refer to the Weights & Biases [Quickstart Guide](https://docs.wandb.ai/quickstart).

Run `0.create-dot-env.sh` to create `.env` file. This file will be sourced by all the subsequent job files:

```bash
0.create-dot-env.sh
```

The script will prompt you to input `WANDB_API_KEY`:

```bash
Setting up environment variables
Please enter your WANDB_API_KEY
xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx # Your API KEY 
.env file created successfully
Please run 'source .env' to set the environment variables
```



The following environment variable will be on `.env` file. Feel free to modify `0.create-dot-env.sh` to customize.

```bash
export FSX_PATH=/fsx
export IMAGE=torchtitan-torchtune
export APPS_PATH=/fsx/apps
export ENROOT_IMAGE=/fsx/apps/torchtitan-torchtune.sqsh
export MODEL_PATH=/fsx/models/torchtitan-torchtune
export TEST_CASE_PATH=/fsx/awsome-distributed-training/3.test_cases/torchtitan-torchtune/slurm
export HF_HOME=/fsx/.cache
export WANDB_CONFIG_DIR=/fsx
export WANDB_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

On the head/login node of the cluster, clone the repository, move to the test case directory.

```bash
source .env
git clone https://github.com/aws-samples/awsome-distributed-training ${FSX_PATH}/awsome-distributed-training
cd ${TEST_CASE_PATH}
```

Clone `torchtitan` and `torchtune`:

```bash
source .env
cd ${TEST_CASE_PATH}
git clone https://github.com/pytorch/torchtitan.git torchtitan
git clone https://github.com/pytorch/torchtune.git torchtune
```

## 2. Build the container

Before running training jobs, you need to use a build docker container image. [Enroot](https://github.com/NVIDIA/enroot) will be used to turn the image into unprivileged sandbox for Slurm. 

Submit `1.build-image.sbatch`:

```bash
sbatch 1.build-image.sbatch
```

You can check build progress through log files:

```bash
tail -f logs/build-image_581.*
```

The build process was successuful if you could see the following lines at the end of the log:

```bash
Number of fifo nodes 0
Number of socket nodes 0
Number of directories 41628
Number of ids (unique uids + gids) 1
Number of uids 1
        root (0)
Number of gids 1
        root (0)

==> logs/build-image_xxx.out <==
Image built and saved as /fsx/apps/torchtitan-torchtune.sqsh
```

## 3. Get access to the Llama3 model

Go to [Meta-Llama-3-70B](https://huggingface.co/meta-llama/Meta-Llama-3-70B) and apply for access. Then, go to [Hugging Face Tokens](https://huggingface.co/settings/tokens) to create an access token.

On the login node, launch a Python process and call `huggingface_hub.login()` as follows:

```bash
source .env
enroot start --env NVIDIA_VISIBLE_DEVICES=void \
    --mount ${FSX_PATH}:${FSX_PATH} ${ENROOT_IMAGE} \
    python -c "from huggingface_hub import login; login()"
```

It will prompt you to input the token. Paste the token and answer to `n` to the following question:

```bash
>> Add token as git credential? (Y/n) n
>> Token is valid (permission: read).
>> Your token has been saved to /fsx/.cache/token
```

As you can see on the output, the access token stored under `/fsx/.cache`.

Now fetch model weights and tokenizer with `2.download_hf_model.sbatch`:

```bash
sbatch 2.download_hf_model.sbatch
```

The model will be downloaded under ${}

## 4. Pretrain Llama3 model

In this step, you will author Llama3 model using c4 dataset with `torchtitan`.

```bash
sbatch 3.pretrain.sbatch
```

## 4. Finetune Llama3 model

In this step, you will fine tune llama model, using Alpaca dataset. 

```bash
sbatch 4.finetune.sbatch
```

Once the job has been completed, you will see following outputs in the log:

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
