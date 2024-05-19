#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH -N 1 # number of nodes to use
#SBATCH --job-name=build-image # name of your job
#SBATCH --output=logs/%x_%j.out # logfile for stdout
#SBATCH --error=logs/%x_%j.err # logfile for stderr, remove it to merge both outputs

set -euo pipefail

if [ ! -f .env ]
then
    echo "Please create a .env file with the required environment variables"
    exit 1
else
    source .env
fi

cd ..
docker build -t ${IMAGE} -f 0.torchtitan-torchtune.dockerfile .

# Remove old sqsh file if exists
if [ -f torchtitan-torchtune.sqsh ] ; then
    rm torchtitan-torchtune.sqsh
fi
enroot import -o torchtitan-torchtune.sqsh dockerd://torchtitan-torchtune:latest
mv torchtitan-torchtune.sqsh ${ENROOT_IMAGE}
echo "Image built and saved as ${ENROOT_IMAGE}"