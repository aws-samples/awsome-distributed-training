#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name=nccl-all_reduce_perf # name of your job
#SBATCH --nodes=2 # number of nodes to use, 24 p4d(e) = 192 A100 GPUs
#SBATCH --ntasks-per-node 8 # Number of GPU per node
#SBATCH --output %x_%j.out
#SBATCH --error %x_%j.err
#SBATCH --exclusive

# This script is designed to run on the Deep Learning AMI, Ubuntu 20.04
# See https://aws.amazon.com/releasenotes/aws-deep-learning-base-gpu-ami-ubuntu-20-04/
set -ex

# Get Hostname to Instance ID mapping
mpirun -N 1 bash -c 'echo $(hostname) ➡️ $(cat /sys/devices/virtual/dmi/id/board_asset_tag | tr -d " ")'


### NCCL_BUFFSIZE increase the send queue depth and can turn NCCL communications into non-blocking.
### https://www.usenix.org/system/files/atc23-choi.pdf

### NCCL_P2P_NET_CHUNKSIZE Improve performance by increasing buffer size for Send/Recv, Gather, Scatter and Alltoall communications
### https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/usage/p2p.html

# run all_reduce test
mpirun -n $((8 * SLURM_JOB_NUM_NODES)) -N 8 \
        -x FI_PROVIDER=efa \
	-x FI_EFA_USE_DEVICE_RDMA=1  \
	-x FI_EFA_FORK_SAFE=1 \
	-x LD_LIBRARY_PATH=/opt/amazon/efa/lib:/opt/amazon/openmpi/lib:/opt/aws-ofi-nccl/lib:/usr/local/lib:/usr/lib:$LD_LIBRARY_PATH \
	-x NCCL_DEBUG=INFO \
	-x NCCL_BUFFSIZE=8388608 \
	-x NCCL_P2P_NET_CHUNKSIZE=524288 \
	--mca pml ^cm,ucx \
	--mca btl tcp,self \
	--mca btl_tcp_if_exclude lo,docker0,veth_def_agent \
	--bind-to none /usr/local/cuda-12.2/efa/test-cuda-12.2/all_reduce_perf -b 8 -e 16G -f 2 -g 1 -c 1 -n 100

