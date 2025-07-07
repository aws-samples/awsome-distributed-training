# Multi-node Large model GRPO training using Hugging Face TRL

## Overview

This is a test case for multi-node large model GRPO training using Hugging Face TRL.

## Prerequisites

### Docker Image

We define all the dependencies in `grpo.Dockerfile` and build the image with the following command:

```bash
docker build -f grpo.Dockerfile -t grpo:latest .
```

### Enroot

To run our container on Slurm we convert the container into a Squash file using Enroot:

```bash
enroot import -o ./grpo.sqsh  dockerd://grpo:latest
```

## Launching GRPO training

We launch the GRPO training with the following command:

```bash
sbatch train.sbatch Qwen/Qwen2.5-72B-Instruct
```

The logs can be inspected using tail command:

GRPO Training logs:
```bash
tail -f -n +0 grpo_XXX.out 
```
sample output:
```
  1%|          | 17/2264 [01:22<2:55:16,  4.68s/it]
0: {'loss': 0.0785, 'grad_norm': 0.8229517735973697, 'learning_rate': 9.916077738515903e-06, 'num_tokens': 1498339.0, 'completions/mean_length': 134.934765625, 'completions/min_length': 35.0, 'completions/max_length': 256.0, 'completions/clipped_ratio': 0.08203125, 'completions/mean_terminated_length': 124.83461303710938, 'completions/min_terminated_length': 35.0, 'completions/max_terminated_length': 253.8, 'rewards/format_reward/mean': 0.90703125, 'rewards/format_reward/std': 0.27258416190743445, 'rewards/accuracy_reward/mean': 0.224609375, 'rewards/accuracy_reward/std': 0.4104481041431427, 'reward': 1.131640625, 'reward_std': 0.34059175848960876, 'kl': 0.2958984375, 'clip_ratio/low_mean': 0.0, 'clip_ratio/low_min': 0.0, 'clip_ratio/high_mean': 0.0, 'clip_ratio/high_max': 0.0, 'clip_ratio/region_mean': 0.0, 'epoch': 0.01}
```

vLLM logs:
```bash
tail -f -n +0 vllm_XXX.out
```
sample output:
```
0: INFO:     10.4.37.27:41696 - "POST /upda_named_param/ HTTP/1.1" 200 OK
0: INFO:     10.4.37.27:41696 - "POST /update_named_param/ HTTP/1.1" 200 OK
0: INFO:     10.4.37.27:41696 - "POST /update_named_param/ HTTP/1.1" 200 OK
0: INFO 05-14 23:13:00 [block_pool.py:264] Successfully reset prefix cache
0: INFO:     10.4.37.27:41696 - "POST /reset_prefix_cache/ HTTP/1.1" 200 OK
Processed prompts: 100%|██████████| 256/256 [00:01<00:00, 176.40it/s, est. speed input: 32916.33 toks/s, output: 13802.34 toks/s]
0: INFO:     10.4.37.27:41696 - "POST /generate/ HTTP/1.1" 200 OK
0: INFO:     10.4.37.27:41696 - "POST /update_named_param/ HTTP/1.1" 200 OK
0: INFO:     10.4.37.27:41696 - "POST /update_named_param/ HTTP/1.1" 200 OK
0: INFO:     10.4.37.27:41696 - "POST /update_named_param/ HTTP/1.1" 200 OK
```

## Inference

```bash
srun --mpi=pmix --cpu-bind=none --container-image ./grpo.sqsh --container-mounts=.:/grpo,$HF_HOME:$HF_HOME --error=infer.err python /grpo/infer.py --model /grpo/.../Qwen/Qwen2.5-14B-Instruct-GRPO/checkpoint-700/
```

## Evaluation

```bash
srun --mpi=pmix --cpu-bind=none --container-image ./grpo.sqsh --container-mounts=.:/grpo,$HF_HOME:$HF_HOME --error=eval.err python /grpo/eval.py --model /grpo/.../Qwen/Qwen2.5-14B-Instruct-GRPO/checkpoint-700/
```