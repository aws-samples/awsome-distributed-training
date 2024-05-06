# Llama3 Test Case  <!-- omit in toc -->

Llama3 is...

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
export ENROOT_IMAGE=$APPS_PATH/llama3.sqsh
export FSX_PATH=/fsx
export MODEL_PATH=$FSX_PATH/llama3
export TEST_CASE_PATH=${FSX_PATH}/awsome-distributed-training/3.test_cases/19.llama-recipes
export HF_HOME=${FSX_PATH}/.cache
export WANDB_CONFIG_DIR=${FSX_PATH}
export WANDB_API_KEY=PUT_YOUR_API_KEY_HERE # You need to place your WANDB_API_KEY here 
EOF
```

On the head/login node of the cluster, clone the repository, move to the test case directory.

```bash
git clone https://github.com/aws-samples/awsome-distributed-training ${FSX_PATH}
cd ${TEST_CASE_PATH}
```

Clone two llama sample repositories

```bash
git clone https://github.com/meta-llama/llama3.git
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
>> Your token has been saved to /home/ubuntu/.cache/huggingface/token
```

As you can see on the output, the access token stored under `/home/ubuntu/.cache/huggingface`.
Move the token to `/fsx/.cache`.


## 4. Finetune Llama3 model

In this step, you will fine tune llama model, using Alpaca dataset

This example making use of W&B experiment tracking. 
by using use_wandb flag as below. You can change the project name, entity and other wandb.init arguments in wandb_config.

The training process will create the following FSDP checkponits.

```bash
$ ls /fsx/models/meta-llama/Meta-Llama-3-8B-tuned/fine-tuned-meta-llama/Meta-Llama-3-8B/
__0_0.distcp   __12_0.distcp  __15_0.distcp  __3_0.distcp  __6_0.distcp  __9_0.distcp
__10_0.distcp  __13_0.distcp  __1_0.distcp   __4_0.distcp  __7_0.distcp  train_params.yaml
__11_0.distcp  __14_0.distcp  __2_0.distcp   __5_0.distcp  __8_0.distcp
```


Use the following command to convert the checkpoint into 

```
    enroot start --env NVIDIA_VISIBLE_DEVICES=void \
        --mount ${FSX_PATH}:${FSX_PATH} ${ENROOT_IMAGE} \
        python ${PWD}/llama-recipes/src/llama_recipes/src/inference/checkpoint_converter_fsdp_hf.py \
        --fsdp_checkpoint_path /fsx/models/meta-llama/Meta-Llama-3-8B-tuned/fine-tuned-meta-llama/Meta-Llama-3-8B \
        --
```


```bash
==> logs/convert-checkpoint_560.out <==
0: Model name: meta-llama/Meta-Llama-3-70B
0: model is loaded from config
0: Sharded state checkpoint loaded from /fsx/models/Meta-Llama-3-70B-tuned/fine-tuned-meta-llama/Meta-Llama-3-70B
0: model is loaded from FSDP checkpoints
0: debug:  meta-llama/Meta-Llama-3-70B <class 'str'>
0: HuggingFace model checkpoints has been saved in /fsx/models/meta-llama/Meta-Llama-3-70B-tuned/fine-tuned-meta-llama/Meta-Llama-3-70B-hf
```

that result in the HF checkpoints

```bash
$ ls /fsx/models/meta-llama/Meta-Llama-3-8B-tuned/fine-tuned-meta-llama/Meta-Llama-3-8B-hf
config.json             model-00001-of-00007.safetensors  model-00003-of-00007.safetensors  model-00005-of-00007.safetensors  model-00007-of-00007.safetensors  special_tokens_map.json  tokenizer_config.json
generation_config.json  model-00002-of-00007.safetensors  model-00004-of-00007.safetensors  model-00006-of-00007.safetensors  model.safetensors.index.json      tokenizer.json
```


## 5. Chat with Finetuned model

This step illustrates how to test Llama3 model deployment on 


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


check instance running the inference server

```bash
$ squeue
JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)
546        p5 serve-vl   ubuntu  R      13:04      1 p5-st-p5-1
```

Now you can query 

```bash
$  curl http://p5-st-p5-1:8000/v1/models
{"object":"list","data":[{"id":"/fsx/models/meta-llama/Meta-Llama-3-8B-tuned/fine-tuned-meta-llama/Meta-Llama-3-8B-hf","object":"model","created":1714698315,"owned_by":"vllm","root":"/fsx/models/meta-llama/Meta-Llama-3-8B-tuned/fine-tuned-meta-llama/Meta-Llama-3-8B-hf","parent":null,"permission":[{"id":"modelperm-5ed883dd35534fd89feb98a182217e3a","object":"model_permission","created":1714698315,"allow_create_engine":false,"allow_sampling":true,"allow_logprobs":true,"allow_search_indices":false,"allow_view":true,"allow_fine_tuning":false,"organization":"*","group":null,"is_blocking":false}]}]}
```

Copy  
```
export MODEL="/fsx/models/meta-llama/Meta-Llama-3-8B-tuned/fine-tuned-meta-llama/Meta-Llama-3-8B-hf"
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


```bash
curl http://p5-st-p5-1:8000/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
        "model": "/fsx/models/meta-llama/Meta-Llama-3-8B-tuned/fine-tuned-meta-llama/Meta-Llama-3-8B-hf",
        "messages": [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": ""}
        ]
    }'
```


Now that you can launch gradio app that queries the endpoint from the login node.

```
bash 5.launch-gradio-app.sh
```

## 6. Evaluate model

In this last section, you will evaluate the model you have trained. 



