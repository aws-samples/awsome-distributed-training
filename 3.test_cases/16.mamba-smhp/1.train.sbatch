#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --nodes=4
#SBATCH --job-name=mamba-pretrain-deepspeed
#SBATCH --exclusive
srun -l train.sh
