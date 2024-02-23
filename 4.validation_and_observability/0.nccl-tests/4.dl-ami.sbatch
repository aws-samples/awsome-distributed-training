#!/bin/bash
#SBATCH -N 2
#SBATCH --exclusive

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# This script is designed to run on the Deep Learning AMI, Ubuntu 20.04
# See https://aws.amazon.com/releasenotes/aws-deep-learning-base-gpu-ami-ubuntu-20-04/
set -ex

# Get Hostname to Instance ID mapping
mpirun -N 1 bash -c 'echo $(hostname) -> $(cat /sys/devices/virtual/dmi/id/board_asset_tag | tr -d " ")'

# run all_reduce test
mpirun -n $((8 * SLURM_JOB_NUM_NODES)) -N 8 \
        -x FI_PROVIDER=efa \
	-x FI_EFA_USE_DEVICE_RDMA=1  \
	-x RDMAV_FORK_SAFE=1 \
	-x LD_LIBRARY_PATH=/opt/amazon/efa/lib:/opt/amazon/openmpi/lib:/opt/aws-ofi-nccl/lib:/usr/local/lib:/usr/lib:$LD_LIBRARY_PATH \
	-x NCCL_DEBUG=INFO \
	--mca pml ^cm \
	--mca btl tcp,self \
	--mca btl_tcp_if_exclude lo,docker0 \
	--bind-to none /usr/local/cuda-12.2/efa/test-cuda-12.2/all_reduce_perf -b 8 -e 2G -f 2 -g 1 -c 1 -n 100
