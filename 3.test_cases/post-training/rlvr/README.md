# rlvr-recipe

This repository provides a complete setup for running reinforcement learning from verifiable rewards (RLVR) on EKS clusters using Ray and verl. RLVR trains language models using verifiable rewards from math and coding tasks, where correctness can be automatically verified. The project uses verl, an efficient RL training framework from ByteDance, to run algorithms like GRPO (Group Relative Policy Optimization) and DAPO (Direct Advantage Policy Optimization) on distributed GPU clusters.

## What is verl?

[verl (Volcano Engine Reinforcement Learning)](https://github.com/volcengine/verl) is a flexible, production-ready RL training library for large language models. It provides seamless integration with popular frameworks like FSDP, Megatron-LM, vLLM, and Ray, enabling efficient distributed training with state-of-the-art throughput. This repo includes the full verl codebase with custom run scripts optimized for HyperPod.

## What is RLVR?

[Reinforcement Learning from Verifiable Rewards (RLVR)](https://arxiv.org/abs/2506.14245) is a training approach where models learn from tasks with objectively verifiable outcomes, such as math problems or code execution. Unlike human preference-based RL, RLVR uses ground-truth correctness as the reward signal, making it particularly effective for reasoning tasks.

## Getting started

From here on out, we will assume you have an EKS cluster with GPU nodes (e.g., p5en.48xlarge).

### Clone this repo
```bash
git clone https://github.com/aws-samples/awsome-distributed-training.git #gitlab or github not sure yet
cd awsome-distributed-training/3.test_cases/post-training/rlvr
```

### Create RayCluster

Install KubeRay operator to manage Ray clusters on Kubernetes:
```bash
./setup/install-kuberay.sh
```

Configure your cluster settings (AWS region, cluster name, GPU counts, model paths):
```bash
vim setup/env_vars
```

Load the environment variables into your shell session:
```bash
source setup/env_vars
```

Build a Docker image with verl, EFA networking support, and push to ECR:
```bash
./setup/build-push.sh
```

Deploy the Ray cluster with head and worker pods configured for distributed training:
```bash
envsubst < setup/raycluster.yaml | kubectl apply -f -
```

Download the GSM8K math dataset and prepare it for GRPO training:
```bash
./setup/load_data_grpo.sh
```

Forward the Ray dashboard to localhost for monitoring training progress:
```bash
./ray-expose.sh
```

Submit a GRPO training job to the Ray cluster. This trains a language model on math reasoning using group relative policy optimization:
```bash
./recipe/run_grpo_configurable.sh
```

The `verl/` directory contains the official verl framework, and `recipe/` includes custom run scripts (`run_grpo_configurable.sh`, `run_dapo_configurable.sh`) that integrate with your environment variables for easy configuration.

### Observability

For EKS:
Please see this documentation to set up Prometheus and Grafana dashboards for Ray clusters: [Using Prometheus & Grafana](https://docs.ray.io/en/latest/cluster/kubernetes/k8s-ecosystem/prometheus-grafana.html)

For HyperPod EKS:
Check out the `observability/` directory to integrate Ray's native metrics dashboards with HyperPod's Amazon Managed Prometheus and Grafana