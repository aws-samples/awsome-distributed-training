## Running SmalLM-1.7B training on a single EC2 instance

The model is small enough to run on a single EC2 instance. In this test case, we guide you through how to run 3D model parallelism with Data Parallelism (DP), Tensor Parallelism (TP), and Pipeline Parallelism (PP).

In this test case, we use DP=2, TP=2, and PP=2 which requires 8 GPUs total (2 x 2 x 2 = 8).

### Prerequisites

Before running this example, you need to build the container image following the guidance in [here](..).

### How to run the distributed

First, export your Hugging Face token as an environment variable:
```bash
export HF_TOKEN="hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

Then run the following command to create configuration json file:

```bash
# 3D Parallelism on 8 GPUs
docker run --rm -v ${PWD}:${PWD} picotron python3 create_config.py \
    --out_dir ${PWD}/conf --exp_name llama-1B-dp2-tp2-pp2 --dp 2 --tp 2 --pp 2  \
    --pp_engine 1f1b --model_name HuggingFaceTB/SmolLM-1.7B --num_hidden_layers 5 \
    --grad_acc_steps 2 --mbs 4 --seq_len 128 --hf_token ${HF_TOKEN}
```

It will create a config file `./conf/llama-1B-dp2-tp2-pp2/config.json` describing training configurations, including model architecuture, training configuration and data set to use.

```bash
# 3D Parallelism on CPU
docker run --gpus all --rm -v ${PWD}:${PWD} -w ${PWD} picotron \
    torchrun --nproc_per_node 8 /picotron/train.py \
    --config ./conf/llama-1B-dp2-tp2-pp2/config.json
```
