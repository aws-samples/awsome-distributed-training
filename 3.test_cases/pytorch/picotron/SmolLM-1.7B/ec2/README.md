## Running SmolLM-1.7B Training with 3D Parallelism on a Single EC2 Instance

This guide demonstrates how to train the SmolLM-1.7B model using 3D parallelism on a single EC2 instance. While the model is relatively small compared to larger language models, it serves as an excellent example to understand and experiment with different types of model parallelism:

- Data Parallelism (DP): Distributes training batches across GPUs
- Tensor Parallelism (TP): Splits model layers across GPUs
- Pipeline Parallelism (PP): Divides model vertically into pipeline stages

In this example, we configure:
- DP=2: Data parallel across 2 groups
- TP=2: Each layer split across 2 GPUs
- PP=2: Model divided into 2 pipeline stages
This configuration requires 8 GPUs total (2 x 2 x 2 = 8), which can be found in instances like p5.48xlarge.

### Prerequisites

Before running this example, you need to:
1. Build the Picotron container image following the guidance in [here](..)
2. Have an EC2 instance with 8 GPUs (e.g., p5.48xlarge)

### How to Run the Distributed Training Job

First, export your Hugging Face token as an environment variable:
