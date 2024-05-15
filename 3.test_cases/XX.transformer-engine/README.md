# Llama FSDP training with FP8(Nvidia Transformer Engine)

[Transformer Engine (TE)](https://github.com/NVIDIA/TransformerEngine) is a library for accelerating Transformer models on NVIDIA GPUs, including using 8-bit floating point (FP8) precision on Hopper GPUs, to provide better performance with lower memory utilization in both training and inference.

This example trains [Hugging Face implementation](https://huggingface.co/docs/transformers/en/model_doc/llama2) of [Meta's Llama model](https://llama.meta.com/) with Fully Sharded Data Parallel using FP8. It combines all [Llama 2 optimizations described in Transformer Engine documentation](https://docs.nvidia.com/deeplearning/transformer-engine/user-guide/examples/te_llama/tutorial_accelerate_hf_llama_with_te.html) with popular distributed training approach [PyTorch FSDP](https://pytorch.org/docs/stable/fsdp.html)

This example derived from FSDP example with the following changes:
* Run the training code in nvidia/pytorch docker container(required by Transformer Engine)
* Bound training code to Llama model only
* Use [the optimized version of Llama model](https://github.com/NVIDIA/TransformerEngine/blob/main/docs/examples/te_llama/te_llama.py)
* Apply Transformer Engine fp8_autocast

This guide assumes that you have the following:

- A functional Slurm cluster on AWS.
- Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
- An FSx for Lustre filesystem mounted on `/fsx`.

It is recommended that you use the templates in the architectures [directory](../../1.architectures)

You will also setup the following variables in your terminal environment.

```bash
export DATA_PATH=/fsx # FSx for Lustre shared file-system
```

Make sure that your current directory is under a shared filesystem such as `/fsx/` or the home directory when using [Parallel Cluster](../../1.architectures/aws-parallelcluster).

1. Copy the file `0.transformer-engine.dockerfile` or its content to your head-node.
2. Build the container image with the command below

```bash
docker build -t transformer-engine -f 0.transformer-engine.dockerfile .
```

3. Once the image is built, you can check if it is present with `docker images`. You should see an output similar to this one:

```
[ec2-user@ip-10-0-10-78 ~]$ docker images
REPOSITORY               TAG       IMAGE ID       CREATED             SIZE
transformer-engine       latest    91dbebf98269   9 seconds ago      22.6GB
```

4. Create the squash file with the command below.

```bash
enroot import -o transformer-engine.sqsh  dockerd://transformer-engine:latest
```

5. Now you copy the file `1.train_llama.sbatch` to your cluster then submit a training jobs with the command below:

```bash
sbatch 1.train_llama.sbatch
```

6. You will see a new file in your current working directory called `slurm-XY.out` where `XY` is a number. This is your output file and will capture the `STDOUT` and `STDERR` from your job. You can check how it progresses via the command `tail -f slurm-XY.out` but with the relevant filename. The file content will be similar to the below:

```
0: 2024-05-15 02:37:59 I [train.py:110] Batch 20 Loss: 8.42184, Speed: 47.06 samples/sec, lr: 0.000100
0: 2024-05-15 02:37:59 I [train.py:110] Batch 21 Loss: 8.26941, Speed: 47.30 samples/sec, lr: 0.000100
0: 2024-05-15 02:37:59 I [train.py:110] Batch 22 Loss: 8.19849, Speed: 47.12 samples/sec, lr: 0.000100
0: 2024-05-15 02:38:00 I [train.py:110] Batch 23 Loss: 7.74492, Speed: 46.86 samples/sec, lr: 0.000100
0: 2024-05-15 02:38:00 I [train.py:110] Batch 24 Loss: 8.46525, Speed: 47.35 samples/sec, lr: 0.000100
0: 2024-05-15 02:38:00 I [train.py:110] Batch 25 Loss: 7.60201, Speed: 47.38 samples/sec, lr: 0.000100
```

7. Change `--fp8=1` to `--fp8=0` in `1.train_llama.sbatch` to turn off Transformer Engine FP8 precision and rerun `sbatch 1.train_llama.sbatch`.

```
0: 2024-05-15 02:44:55 I [train.py:110] Batch 20 Loss: 8.82996, Speed: 30.46 samples/sec, lr: 0.000100
0: 2024-05-15 02:44:55 I [train.py:110] Batch 21 Loss: 8.17265, Speed: 30.71 samples/sec, lr: 0.000100
0: 2024-05-15 02:44:56 I [train.py:110] Batch 22 Loss: 7.92729, Speed: 30.63 samples/sec, lr: 0.000100
0: 2024-05-15 02:44:56 I [train.py:110] Batch 23 Loss: 7.75582, Speed: 30.64 samples/sec, lr: 0.000100
0: 2024-05-15 02:44:57 I [train.py:110] Batch 24 Loss: 8.72653, Speed: 30.56 samples/sec, lr: 0.000100
0: 2024-05-15 02:44:57 I [train.py:110] Batch 25 Loss: 7.79590, Speed: 30.78 samples/sec, lr: 0.000100
```

It's noticeable that Transformer Engine fp8 precision gives more than 50% speedup.
