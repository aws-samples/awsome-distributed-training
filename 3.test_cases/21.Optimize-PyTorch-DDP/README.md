# Optimize PyTorch DDP

For a given model size benchmark:
1. Baseline DDP Training of Llama 7b
2. Impact of bucket_cap_mb
3. Impact of param_to_hook_all_reduce

## Baseline DDP

Reproduce Llama training example with DistributedDataParallel

## Hook all reduce
The main drawback of the naive DDP approach we’ve just described is that after the backward pass (computation), we have to wait for gradient synchronization (communication) before updating the parameters. Could we overlap this communication with our computation? The answer is yes! This can be achieved in pytorch by attaching an all-reduce hook function to each parameter. An all-reduce operation is triggered as soon as the gradient for that parameter is ready, while gradients for other parameters are still being computed. This approach overlaps most of the all-reduce operations with gradient calculations, thereby improving efficiency. 

## Bucketing gradients

GPU operations are usually more efficient when performed on large tensors rather than having many operations running on smaller tensors. This is also true for communication operations. Thus, we can advantageously group gradients into buckets and launch a single all-reduce for all the gradients within the same bucket instead of performing independent all-reduce for each gradient.

# Memory optimization

How big models and sequence lengths can we train?

Activastion memory vs Sequence Length

1. Gradient accumulation
2. CPU offloading
3. Activation checkpointing

