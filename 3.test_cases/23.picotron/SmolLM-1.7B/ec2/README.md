## Running SmalLM-1.7B training on a single EC2 instance

The model is small enough to run on a single EC2 instance. In this test case, we duide you through how to run 

In this test case, we use DP=2, TP=2, and PP=2 

```bash
# 3D Parallelism on CPU
docker run --rm -v ${PWD}:${PWD} picotron python3 create_config.py \
    --out_dir ${PWD}/conf --exp_name llama-1B-cpu-dp2-tp2-pp2 --dp 2 --tp 2 --pp 2  \
    --pp_engine 1f1b --model_name HuggingFaceTB/SmolLM-1.7B --num_hidden_layers 5 \
    --grad_acc_steps 2 --mbs 4 --seq_len 128 --hf_token ${HF_TOKEN} --use_cpu  --use_wandb
```

```bash
# 3D Parallelism on CPU
docker run --rm -v /fsx:/fsx -w ${PWD} picotron \
    nsys profile  \
    --output ./nsight-report.nsys-rep \
    torchrun --nproc_per_node 8 ../../train.py \
    --config ../conf/llama-1B-cpu-dp2-tp2-pp2/config.json
```