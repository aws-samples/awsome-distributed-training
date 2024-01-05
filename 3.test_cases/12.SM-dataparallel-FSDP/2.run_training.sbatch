#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --nodes=2
#SBATCH --job-name=smddp-fsdp
#SBATCH --exclusive

srun -l exec_torchrun.sh
