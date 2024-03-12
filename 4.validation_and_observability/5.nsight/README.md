# Profile Distributed Training Applications with Nsight

[Nsight Systems](https://developer.nvidia.com/nsight-systems) is a statistical sampling profiler with tracing features.

# 0. Prerequisities
1. A slurm or Kubernetes cluster is created
2. The compute nodes have nsight installed

# 1. Installation
Get the latest Nsight 2024.2.1 version from S3 and place it in `/fsx` like below after ssh into the head node. The `nsight-efa`folder will have the necessary dependencies for the `host` which is the head node in a Slurm cluster from which the user works and controls the profiling session and `target` which refers to the GPU on which profiling happens. This latest version also has the `nic_sampler` in `/nsight-efa/target-linux-x64/plugins/` which collects the EFA metrics.

```bash
mkdir -p /fsx/nsight-efa
aws s3 cp s3://awsankur-nsight/nsight-efa/ /fsx/nsight-efa/
```

# 2. Profiling NCCL tests
In this section we will show how to generate Nsight reports for NCCL tests. Follow the instructions [here](https://github.com/aws-samples/awsome-distributed-training/tree/main/4.validation_and_observability/0.nccl-tests) to setup NCCL tests and generate the Enroot image `nccl.sqsh`. The `0.nsight_nccl.sbatch` script shows an example on how to profile the NCCL run with Nsight and collect EFA metrics. Key differences between `0.nsight_nccl.sbatch` and [this](https://github.com/aws-samples/awsome-distributed-training/blob/main/4.validation_and_observability/0.nccl-tests/1.nccl-tests.sbatch) are:

1. `/fsx` needs to be mounted to the container as this is where our Nsight binaries are located.
2. The `0.nsight_nccl.sbatch` script references the executable `nsys-slurm-exec` which is given below and should exist in `/fsx`

```bash
#! /bin/bash -x

NSYS_EXTRAS=""
if [ "$SLURM_LOCALID" == "0" ]; then
NSYS_EXTRAS="--enable nic_sampler,-mode:counters,-struct:true,-efa:true"
fi

/fsx/nsight-efa/target-linux-x64/nsys profile $NSYS_EXTRAS --sample none --delay <DELAY-PERIOD> \
    --force-overwrite true --output <PATH-TO-SAVE-REPORT>/report_<REPORT-NAME-TAG>_job%q{SLURM_JOB_ID}_rank%q{SLURM_PROCID}_on_%q{HOSTNAME}.nsys-rep \
   "$@"
```
The above executable needs the following:

```bash
1. DELAY-PERIOD: Collection start delay in seconds. Typically the multi-node workload takes a few seconds before collection of relevant metrics start. Typically for distributed training applications delaying by ~30sec avoids having empty gaps in the timeline view of the re
```






# 3. Multi-node training with Slurm and Pyxis

We will use the [BioNemo](https://github.com/aws-samples/awsome-distributed-training/tree/main/3.test_cases/14.bionemo) test case.

Follow the BioNemo use case to make sure you can run the example. Then to profile the training run, execute

```bash
sbatch 0.nsys_bionemo.slurm

```

You can modify the srun command:

```bash
srun -l "${ARGS[@]}" /usr/local/cuda/bin/nsys profile --output /fsx/nsys_profiles/ --stats true <PYTHON-CODE> --<PYTHON-CODE-ARGS>
```

# 4. Sample stats

Example slurm output file provided: `slurm-esm1nv-train-102.out`

1. 'cuda_api_sum' stats report
2. 'cuda_gpu_mem_time_sum' stats report
3. 'osrt_sum' stats report
4. 'cuda_gpu_kern_sum' stats report
5. 'nvtx_sum' stats report