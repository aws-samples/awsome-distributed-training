# DDP PyTorch
[Param benchmark](https://github.com/facebookresearch/param/tree/main) is a PyTorch benchmark for computation ([GEMM, MLP, EmbeddingBag](https://github.com/facebookresearch/param/tree/6236487e8969838822b52298c2a2318f6ac47bbd/train/compute/pt)), communication ([NCCL, DLRMs, TraceReplay](https://github.com/facebookresearch/param/tree/6236487e8969838822b52298c2a2318f6ac47bbd/train/comms/pt)), workloads ([DLRM](https://github.com/facebookresearch/param/tree/6236487e8969838822b52298c2a2318f6ac47bbd/train/workloads), [training](https://github.com/facebookresearch/param/tree/6236487e8969838822b52298c2a2318f6ac47bbd/train/compute/python)). This guide only addresses communications but serves as an template for other tests.

# 0. Preparation

This guide assumes that you have the following:

- A functional Slurm cluster on AWS.
- Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
- A shared directory mounted on `/apps`

It is recommended that you use the templates in the architectures [directory](../../1.architectures)


## 1. Build the Squash file

The [AWS Deep learning containers](https://aws.amazon.com/machine-learning/containers/) is used as a base for this project and the Param benchmark is built on top of it following the steps below. It is assumed that you copied the assets (`Dockerfile` and `sbatch` file) to your cluster.

1. Login to AWS ECR with command bellow
   ```bash
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 763104351884.dkr.ecr.us-east-1.amazonaws.com
   ```
2. Build the container image with the command below
   ```bash
   docker build -t param-benchmark -f 0.param-benchmark.Dockerfile .
   ```
3. Convert the container image to a squash file via Enroot
   ```bash
   enroot import -o /apps/param-benchmark.sqsh  dockerd://param-benchmark:latest
   ```
   The file will be stored in the `/apps` directory.

> **Note**: We use specific commit due to lack of versioning of param benchmark, which would otherwise be used to pin the dependency.

## 2. Running a communications test

Ensure that the submission file `1.param-benchmark.sbatch` has been copied to your cluster and your shell points to the directory where this file is present. Run the Param benchmark on 2 nodes as follows:

```bash
sbatch -N 2 --export=NONE 1.param-benchmark-comms.sbatch
```

The command will return a job ID. If you stay in the same directory where `sbatch` was called, assuming that your job is executing (or has executed) you will find a output file for your job names `param_benchmark_<ID>.out` where ID corresponds to your job ID.

We add `--export=NONE` parameter to make sure any conflicting environment variable from AMI is not exported to container.

> **Note**: the number of nodes used for the job is defined via the command line with the option and argument `-N 2`. An alternative is to set it in the `sbatch` file as the directive `#SBATCH -N 2`.

You will see NCCL test outputs in the logs (in your local directory), refer to [NCCL-tests](https://github.com/NVIDIA/nccl-tests/blob/master/doc/PERFORMANCE.md) documentation to understand the difference between `AlbBW` and `BusBw`. Review the Param [documentation](https://github.com/facebookresearch/param/tree/6236487e8969838822b52298c2a2318f6ac47bbd/train/comms/pt) for other CLI parameters and other benchmarks in the [repository](https://github.com/facebookresearch/param/tree/6236487e8969838822b52298c2a2318f6ac47bbd) for more communication and computation tests (example [here](https://github.com/facebookresearch/param/blob/6236487e8969838822b52298c2a2318f6ac47bbd/train/compute/pt/README.md) or [here](https://github.com/facebookresearch/param/tree/6236487e8969838822b52298c2a2318f6ac47bbd/train/comms/pt)).

## 3. Other Param tests

Param contains several tests that you can use to evaluate your system. Run the command below to execute single node compute tests for GEMM (Matrix Multiply), EmbeddingBag and MLP.

```bash
sbatch -N 1 --export=NONE 2.param-benchmark-compute.sbatch
```

You should see an output similar to the sample below (MatMult):

```
0: Measuring the performance of  gemm  on device =  gpu
0: Steps =  100  warmups =  10
0: with matrix dataset  A , Data type:  float32
0:
0: ----------------------------------------------------------------
0:          M         N          K          Time(s)      Rate(TF/s)
0: ----------------------------------------------------------------
0:        128,       4096,       4096,       0.000326     13.158
0:        256,       4096,       4096,       0.000610     14.077
0:        512,       4096,       4096,       0.001197     14.347
0:       1024,       4096,       4096,       0.001845     18.624
0:        128,       1024,       1024,       0.000030     8.803
0:        256,       1024,       1024,       0.000048     11.107
0:        512,       1024,       1024,       0.000078     13.700
0:       1024,       1024,       1024,       0.000130     16.558
0:       4096,       4096,        128,       0.000238     18.022
0:       4096,       4096,        256,       0.000462     18.584
0:       4096,       4096,        512,       0.000912     18.829
0:       4096,       4096,       1024,       0.001814     18.942
0:       1024,       1024,        128,       0.000026     10.282
0:       1024,       1024,        256,       0.000040     13.291
0:       1024,       1024,        512,       0.000071     15.208
```

## Authors / Reviewers

- [A] Uros Lipovsek - lipovsek@
- [R] Pierre-Yves Aquilanti - pierreya@
