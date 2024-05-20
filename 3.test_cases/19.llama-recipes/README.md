# Llama-recipes Test Case  <!-- omit in toc -->

In this test case, you will learn how to:
* finetune llama3 model
* evaluate llama3 model on lm-evaluation-harness
* test llama3 model deployment using vLLM

## 1. Preparation

This guide assumes that you have the following:

* A functional Slurm cluster on AWS.
* Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
* An FSx for Lustre filesystem mounted on `/fsx`.

We recommend that you set up a Slurm cluster using the templates in the architectures [directory](../../1.architectures). You need to set the following environment variables to run this test case.
Modify the following snipet and prepare `.env` file. You can always load the variables with `source .env`:

```bash
cat > .env << EOF
export APPS_PATH=/fsx/apps
export ENROOT_IMAGE=\$APPS_PATH/llama3.sqsh
export FSX_PATH=/fsx
export MODEL_PATH=\$FSX_PATH/llama3
export TEST_CASE_PATH=\${FSX_PATH}/awsome-distributed-training/3.test_cases/19.llama-recipes
export HF_HOME=\${FSX_PATH}/.cache
export WANDB_CONFIG_DIR=\${FSX_PATH}
export WANDB_API_KEY=PUT_YOUR_API_KEY_HERE # You need to place your WANDB_API_KEY here 
EOF
```

On the head/login node of the cluster, clone the repository, move to the test case directory.

```bash
git clone https://github.com/aws-samples/awsome-distributed-training ${FSX_PATH}
cd ${TEST_CASE_PATH}
```

Clone llama sample repository:

```bash
git clone https://github.com/meta-llama/llama-recipes.git
```

## 2. Build the container

Before running training jobs, you need to use a build docker container image. [Enroot](https://github.com/NVIDIA/enroot) will be used to turn the image into unprivileged sandbox for Slurm. 
You can build the image on your login node using the option 1 below, but build step may exceed the storage available on the head node so we reccomend building it on a compute node following instructions in option2.

### Option 1: Bulid image on login node

Below are the steps you need to follow:


1. Build the Docker image with the command below in this directory.

   ```bash
    docker build -t llama3 -f 0.llama3.dockerfile .
   ```

## 3. Get access to the Llama3 model

Go to https://huggingface.co/meta-llama/Meta-Llama-3-70B and apply for the access
Go to https://huggingface.co/settings/tokens to create access token. 

In the login node, launch Python process on the head node, run the following:

```bash
    enroot start --env NVIDIA_VISIBLE_DEVICES=void \
        --mount ${FSX_PATH}:${FSX_PATH} ${ENROOT_IMAGE} \
        python -c "from huggingface_hub import login; login()"
```

It will prompt you to input the token. Paste the token and answer to `n` to the following question:

```bash
>> Add token as git credential? (Y/n) n
>> Token is valid (permission: read).
>> Your token has been saved to /fsx/.cache/huggingface/token
```

As you can see on the output, the access token stored under `/fsx/.cache/huggingface`.


## 4. Finetune Llama3 model

In this step, you will fine tune llama model, using Alpaca dataset. Use curl command to download the dataset:

```bash
curl https://raw.githubusercontent.com/tatsu-lab/stanford_alpaca/main/alpaca_data.json
```

This example making use of W&B experiment tracking. 

The training process will create the following FSDP checkponits.

```bash
$ ls /fsx/models/meta-llama/Meta-Llama-3-8B-tuned/fine-tuned-meta-llama/Meta-Llama-3-8B/
__0_0.distcp   __12_0.distcp  __15_0.distcp  __3_0.distcp  __6_0.distcp  __9_0.distcp
__10_0.distcp  __13_0.distcp  __1_0.distcp   __4_0.distcp  __7_0.distcp  train_params.yaml
__11_0.distcp  __14_0.distcp  __2_0.distcp   __5_0.distcp  __8_0.distcp
```


Use the following command to convert the checkpoint into Huggingface format (change value for the arguments based on your setting).

```bash
sbatch 3.convert-checkpoints.sbatch \
    --fsdp_checkpoint_path /fsx/models/Meta-Llama-3-70B-tuned/fine-tuned-meta-llama/Meta-Llama-3-70B \
    --consolidated_model_path /fsx/models/meta-llama/Meta-Llama-3-70B-tuned/fine-tuned-meta-llama/Meta-Llama-3-70B-hf
```

Once the job has been completed you will see following outputs in the log:

```bash
==> logs/convert-checkpoint_560.out <==
0: Model name: meta-llama/Meta-Llama-3-70B
0: model is loaded from config
0: Sharded state checkpoint loaded from /fsx/models/Meta-Llama-3-70B-tuned/fine-tuned-meta-llama/Meta-Llama-3-70B
0: model is loaded from FSDP checkpoints
0: debug:  meta-llama/Meta-Llama-3-70B <class 'str'>
0: HuggingFace model checkpoints has been saved in /fsx/models/meta-llama/Meta-Llama-3-70B-tuned/fine-tuned-meta-llama/Meta-Llama-3-70B-hf
```

and HF checkpoints under `consolidated_model_path`:

```bash
$ ls /fsx/models/meta-llama/Meta-Llama-3-8B-tuned/fine-tuned-meta-llama/Meta-Llama-3-8B-hf
config.json             model-00001-of-00007.safetensors  model-00003-of-00007.safetensors  model-00005-of-00007.safetensors  model-00007-of-00007.safetensors  special_tokens_map.json  tokenizer_config.json
generation_config.json  model-00002-of-00007.safetensors  model-00004-of-00007.safetensors  model-00006-of-00007.safetensors  model.safetensors.index.json      tokenizer.json
```


## 5. Chat with Finetuned model

Now that you can test the finetuned-model deployment using vLLM. 

```bash
sbatch 4.serve-vllm.sbatch
```


It takes few minutes until endpoint become ready. Check the log file and wait untill you see the following lines:

```
==> logs/serve-vllm_546.err <==
0: Special tokens have been added in the vocabulary, make sure the associated word embeddings are fine-tuned or trained.
0: INFO:     Started server process [3554353]
0: INFO:     Waiting for application startup.
0: INFO:     Application startup complete.
0: INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)

==> logs/serve-vllm_546.out <==
0: INFO 05-03 00:53:42 metrics.py:229] Avg prompt throughput: 0.0 tokens/s, Avg generation throughput: 0.0 tokens/s, Running: 0 reqs, Swapped: 0 reqs, Pending: 0 reqs, GPU KV cache usage: 0.0%, CPU KV cache usage: 0.0%
0: INFO 05-03 00:53:52 metrics.py:229] Avg prompt throughput: 0.0 tokens/s, Avg generation throughput: 0.0 tokens/s, Running: 0 reqs, Swapped: 0 reqs, Pending: 0 reqs, GPU KV cache usage: 0.0%, CPU KV cache usage: 0.0%
0: INFO 05-03 00:54:02 metrics.py:229] Avg prompt throughput: 0.0 tokens/s, Avg generation throughput: 0.0 tokens/s, Running: 0 reqs, Swapped: 0 reqs, Pending: 0 reqs, GPU KV cache usage: 0.0%, CPU KV cache usage: 0.0%
```
Now check which instance running the inference server:

```bash
$ squeue
JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)
546        p5 serve-vl   ubuntu  R      13:04      1 p5-st-p5-1
```

You can query to the host:

```bash
$  curl http://p5-st-p5-1:8000/v1/models
{"object":"list","data":[{"id":"/fsx/models/meta-llama/Meta-Llama-3-8B-tuned/fine-tuned-meta-llama/Meta-Llama-3-8B-hf","object":"model","created":1714698315,"owned_by":"vllm","root":"/fsx/models/meta-llama/Meta-Llama-3-8B-tuned/fine-tuned-meta-llama/Meta-Llama-3-8B-hf","parent":null,"permission":[{"id":"modelperm-5ed883dd35534fd89feb98a182217e3a","object":"model_permission","created":1714698315,"allow_create_engine":false,"allow_sampling":true,"allow_logprobs":true,"allow_search_indices":false,"allow_view":true,"allow_fine_tuning":false,"organization":"*","group":null,"is_blocking":false}]}]}
```

Then you can query

```bash
curl http://p5-st-p5-1:8000/v1/completions     -H "Content-Type: application/json"     -d '{
        "model": "/fsx/models/meta-llama/Meta-Llama-3-70B-tuned/fine-tuned-meta-llama/Meta-Llama-3-70B-hf",
        "prompt": "<|im_start|>user\n How can I launch a virtual server?<|im_end|>",
        "max_tokens": 20,
        "temperature": 0
    }'
```

then you get

```bash
{"id":"cmpl-c6758a500e16474e95c175df02a14cdb","object":"text_completion","created":1714699824,"model":"/fsx/models/meta-llama/Meta-Llama-3-8B-tuned/fine-tuned-meta-llama/Meta-Llama-3-8B-hf","choices":[{"index":0,"text":" city of many cultures. It is home to a variety of people from all backgrounds, including people from","logprobs":null,"finish_reason":"length","stop_reason":null}],"usage":{"prompt_tokens":5,"total_tokens":25,"completion_tokens":20}}
```


Now that you can launch gradio app that queries the endpoint from the login node.

```
bash 5.launch-gradio-app.sh
```


## 6. Evaluate model

In this last section, you will evaluate Llama models. It will make use of [lm-evaluation-harness](https://github.com/EleutherAI/lm-evaluation-harness). 

You can submit sample evaluation job by:

```bash
sbatch 6.evaluate.sbatch
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



