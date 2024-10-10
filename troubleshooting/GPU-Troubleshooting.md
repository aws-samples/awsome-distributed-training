# GPU Troubleshooting Guide

This guide presents how to identify and resolve issues on Amazon EC2 instances with NVIDIA GPUs.

While running High-Performance Computing or Machine Learning workloads, GPUs may fail for various reasons captured by Xid messages.
Those messages are placed in `/var/log/messages` for Amazon Linux or for Ubuntu in `/var/log/syslog` and `/var/log/kern.log`

| Xid | Failure                                                                                           | Resolution          | Orchestrator                                            |
| --- | ------------------------------------------------------------------------------------------------- | ------------------- | ------------------------------------------------------- |
| 48  | Double Bit ECC                                                                                    | Terminate instances | [AWS ParallelCluster](#Terminate-and-replace-instances) |
| 64  | ECC page retirement or row remapper recording failure<br> All reserved rows for bank are remapped | Terminate instances | [AWS ParallelCluster](#Terminate-and-replace-instances) |
|     |                                                                                                   |                     |                                                         |
| 79  | GPU has fallen off the bus                                                                        | Reboot              |                                                         |
| 94  | Contained ECC error                                                                               | Reset GPUs          | [AWS ParallelCluster](#reset-gpus)                      |
| 95  | Uncontained ECC error                                                                             | Reset GPUs          | [AWS ParallelCluster](#reset-gpus)                      |
| 120 | GSP Error                                                                                         | Terminate instances | [AWS ParallelCluster](#Terminate-and-replace-instances) |

# AWS ParallelCluster

## Terminate and replace instances

1. Create a reservation to isolate the node from being used by any jobs.

   ```bash
   sudo /opt/slurm/bin/scontrol create res starttime=now duration=infinite flags=ignore_jobs user=root nodes=[NODE_TO_TERMINATE]
   ```

1. Identify jobs using nodes to terminate

   ```bash
   squeue -w [NODE_TO_TERMINATE] -o %A -h
   ```

1. Cancel

   ```bash
   scancel [JOB_ID]
   ```

1. Place the node in **DRAIN**.

   ```bash
   sudo /opt/slurm/bin/scontrol update node=[NODE_TO_TERMINATE] state=drain reason=gpus-fail
   ```

   The node will have a **DRAIN** status. Then the instance will be terminated and replaced.

1. Delete the reservation

   ```bash
   sudo /opt/slurm/bin/scontrol delete res root_[RES_NUMBER]
   ```

## Reset GPUs

1. Create a reservation to isolate the node from being used by any jobs.

   ```bash
   sudo /opt/slurm/bin/scontrol create res starttime=now duration=infinite flags=ignore_jobs user=root nodes=[NODE_TO_TERMINATE]
   ```

1. Identify jobs using nodes to terminate

   ```bash
   squeue -w [NODE_TO_TERMINATE] -o %A -h
   ```

1. Cancel

   ```bash
   scancel [JOB_ID]
   ```

1. Reset the GPUs

   ```bash
   sudo /opt/slurm/bin/srun -w [NODE_TO_TERMINATE] nvidia-smi -r
   ```

1. Delete the reservation

   ```bash
   sudo /opt/slurm/bin/scontrol delete res root_[RES_NUMBER]
   ```

# Amazon SageMaker HyperPod

TBD

# Amazon EKS

TBD
