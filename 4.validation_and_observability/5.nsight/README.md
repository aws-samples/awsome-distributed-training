# Profile Distributed Training Applications with Nsight

[Nsight Systems](https://developer.nvidia.com/nsight-systems) is a statistical sampling profiler with tracing features.

# 0. Prerequisities
1. A slurm or Kubernetes cluster is created
2. The compute nodes have nsight installed

# 1. Installation
We have a Pcluster created with the Base Ubuntu AMI that has `nsight-systems-2023.2.3` pre-installed. We will use the `nsys` binary in `/usr/local/cuda/bin`.

# 2. Multi-node training with Slurm and Pyxis

We will use the [BioNemo](https://github.com/aws-samples/awsome-distributed-training/tree/main/3.test_cases/14.bionemo) test case.

Follow the BioNemo use case to make sure you can run the example. Then to profile the training run, execute

```bash
sbatch 0.nsys_bionemo.slurm

```

You can modify the srun command:

```bash
srun -l "${ARGS[@]}" /usr/local/cuda/bin/nsys profile --output /fsx/nsys_profiles/ --stats true <PYTHON-CODE> --<PYTHON-CODE-ARGS>
```

# 3. Sample stats

Example slurm output file provided: `slurm-esm1nv-train-102.out`

1. 'cuda_api_sum' stats report
2. 'cuda_gpu_mem_time_sum' stats report
3. 'osrt_sum' stats report
4. 'cuda_gpu_kern_sum' stats report
5. 'nvtx_sum' stats report