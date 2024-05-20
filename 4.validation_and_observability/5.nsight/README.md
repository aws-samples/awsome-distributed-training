# Profile Distributed Training Applications with Nsight 

[Nsight Systems](https://developer.nvidia.com/nsight-systems) is a system-wide performance analysis tool designed to profile and visualize multi-node CPU and GPU workloads such as distributed training and inference to identify the largest opportunities to optimize, and tune to scale efficiently across the cluster. It also enables researchers to add their own markers into their code to surface application-level metrics into the profiler and gain further observability.

We will show how to profile and analyze:

1. [NCCL Tests](https://github.com/aws-samples/awsome-distributed-training/tree/main/micro-benchmarks/nccl-tests/slurm)
2. [Distributed training run with NeMo](https://github.com/aws-samples/awsome-distributed-training/tree/main/3.test_cases/2.nemo-launcher)
3. [Distributed training run with FSDP](https://github.com/aws-samples/awsome-distributed-training/tree/main/3.test_cases/10.FSDP)
4. Setup Nsight on an EKS cluster

# 0. Prerequisities

1. A cluster created with P4de or P5 nodes with AWS ParallelCluster or EKS
2. Before profiling the above workloads, make sure you can run them on your cluster.
3. For EKS, we will be using a 2 node P4de cluster with EFA enabled and FSx for Lustre mounted on the cluster

# 1. Export Environment Variables

Export the following variables to setup the profiling:

```bash
# Nsight Version
export Nsight_version=2024.3.1
export Nsight_cli_installer=NsightSystems-linux-cli-public-2024.3.1.75-3419530.deb
export Nsight_download_url=https://developer.nvidia.com/downloads/assets/tools/secure/nsight-systems/2024_3/NsightSystems-linux-cli-public-2024.3.1.75-3419530.deb
export Nsight_Path=/fsx/nsight-efa
```

# 2. Installation

If you created the cluster with DLAMI or are using the default ParallelCluster base image, Nsight comes pre-installed. You can check the version in the `/usr/local/cuda/` folder you should see `nsight-systems-202x.x.x` folder. ParallelCluster 3.8.0 has the version 2023.2 version pre-installed. 

To get the latest Nsight 2024.3 version from [here](https://developer.nvidia.com/nsight-systems/get-started). If you are installing it on a remote cluster, then the CLI version would suffice. To install it on a Ubuntu based OS node:

```bash
# Download Nsight CLI
wget ${Nsight_download_url}

# Install
sudo dpkg -i ${Nsight_cli_installer}

# This would place the nsys binay at /opt/nvidia/nsight-systems-cli/2024.3.1/target-linux-x64/nsys
# Move to FSx filesystem
cp -r /opt/nvidia/nsight-systems-cli/${Nsight_version}/* ${Nsight_Path}
```

The `nsight-efa`folder will have the necessary dependencies for the `host` which is the head node in a Slurm cluster from which the user works and controls the profiling session and `target` which refers to the GPU on which profiling happens. This latest version also has the `nic_sampler` in `/nsight-efa/target-linux-x64/plugins/` which collects the EFA metrics.

Note, the 2024.4 versionof Nsight will be released by 5/24/2024.

# 3. Profiling NCCL tests
In this section we will show how to generate Nsight reports for NCCL tests. Follow the instructions [here](https://github.com/aws-samples/awsome-distributed-training/tree/main/4.validation_and_observability/0.nccl-tests) to setup NCCL tests and generate the Enroot image `nccl.sqsh`. The `0.nsight_nccl.sbatch` script shows an example on how to profile the NCCL run with Nsight and collect EFA metrics. Key differences between `0.nsight_nccl.sbatch` and [this](https://github.com/aws-samples/awsome-distributed-training/blob/main/4.validation_and_observability/0.nccl-tests/1.nccl-tests.sbatch) are:

1. `/fsx` needs to be mounted to the container as this is where our Nsight binaries are located.
2. The `0.nsight_nccl.sbatch` script references the executable `nsys-slurm-exec` which is given below and should exist in `/fsx`

```bash
#! /bin/bash -x

NSYS_EXTRAS=""
if [ "$SLURM_LOCALID" == "0" ]; then
NSYS_EXTRAS="--enable efa_metrics"
fi

/fsx/nsight-efa/target-linux-x64/nsys profile $NSYS_EXTRAS --sample none --delay <DELAY-PERIOD> \
    --force-overwrite true --output <PATH-TO-SAVE-REPORT>/report_<REPORT-NAME-TAG>_job%q{SLURM_JOB_ID}_rank%q{SLURM_PROCID}_on_%q{HOSTNAME}.nsys-rep \
   "$@"
```
The above executable needs the following:

```bash
1. DELAY-PERIOD: Collection start delay in seconds. Typically the multi-node workload takes a few seconds before collection of relevant metrics start. Typically for distributed training applications delaying by ~30sec avoids having empty gaps in the timeline view of the Nsight report. For the NCCL test a delay of less than 5 seconds works. You can also specify --duration in seconds to collect metrics.

2. PATH-TO-SAVE-REPORT: One report is generated per GPU. Provide a path to save all reports.
3. REPORT-NAME-TAG: Unique name tag to group all reports.
```
Here, we are running the Nsight profile with 2 p4de nodes where each node has 4 EFA devices and 8 GPUs. The `nic sampler` metrics from all 4 EFA devices show up in every report so it is okay to collect these metrics only for 1 rank.

Below is a screenshot of the generated Nsight report:

<center><img src="nccl/NCCL_Scatter_Perf.png" width="80%"/> </br>
</center>

Here there are the following things to note:

•   The RDMA read bytes per second shown in green are from the EFA NIC samplers. You can see there are 4 `rdma*` rows in the report, one corresponding to each of the EFA devices one 1 node. For a P5.48xlarge node, you will see 32 rows.
•   This report is generated for the [Scatter Performance NCCL test](https://github.com/NVIDIA/nccl-tests/blob/2cbb968101e2bfc7d3a7f0f1826c0189355de6fe/src/scatter.cu#L34), which essentially calls the ncclSendRecv kernels again and again which is why ncclDevKernel_SendRecv takes 99.3% utilization among all kernels.
•   You can right click on any row to see the meta-data over time in the Events View which shows start times, durations and other meta-data for each kernel

> [!TIP]
> The *.qdstrm files are temporarily generated first using the nsys binaries in `.../target-linux-x64` while the `*.nsys-rep` report file is generated using the `/host-linux-x64/QdstrmImporter` binary. If for some reason, only `*.qdstrm` files are generated, use the above importer like below to generate a `*.nsys-rep report`
```bash
<Path-to-host-linux-x64>/host-linux-x64/QdstrmImporter –input-file <file-name>.qdstrm
```


## 3.1 NCCL All Reduce Test

Following the steps above, you can generate a similar result for NCCL All Reduce Test also see NCCL test output in the logs. Here we will visualize the spread in NCCL All Reduce communication for 1GB and 2GB message sizes. To do so you can:
1. Run NCCL test and generate report. Save the result for 1GB and 2GB message sizes.
2. Right click on `all_reduce_perf > NCCL` row to show in Events View. This Events View shows NCCL Kernel API calls on the CPU. You can see the NCCL Message Size for each call. Note row numbers where NCCL Message Sizes change.
3. Right click on `ncclDevKernel_AllReduce_Sum_f32_TREE_LL(ncclDevComm *, unsigned long, ncclWork *)` row and show in Events View. This Events View shows NCCL Kernel calls executed on the GPU, it start time and duration. Copy paste the entire table in a csv.
4. You should see 1-on-1 correlation between 3 and 4. Meaning for each NCCL call on the CPU there is a call executed on the GPU. Or in other words, the number of rows in Events View from 3 and 4 should exactly be the same.
5. Add NCCL Message Sizes from Step 3 to csv from Step 4. Save the csv as `all_reduce.csv` which should look like below:

<center><img src="nccl/all_reduce_csv_screenshot.png" width="80%"/> </br>
</center>

You can generate the plot below using the python script `/nccl/plot_nccl.py`

<center><img src="nccl/all_reduce_sum.png" width="80%"/> </br>
</center>

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