#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH -N 1 # number of nodes to use
#SBATCH --job-name=build-neox-image # name of your job
#SBATCH --output=logs/%x_%j.out # logfile for stdout
#SBATCH --error=logs/%x_%j.err # logfile for stderr, remove it to merge both outputs

set -euxo pipefail

# default variables for Enroot, if these variables are defined then use them
: "${APPS_PATH:=/fsx/apps}"
: "${IMAGE:=$APPS_PATH/gpt-neox.sqsh}"

ENROOT_IMAGE=gpt-neox
docker build -t ${ENROOT_IMAGE} -f 0.gpt-neox.dockerfile .
# Remove old sqsh file if exists
if [ -f ${ENROOT_IMAGE}.sqsh ] ; then
    rm ${ENROOT_IMAGE}.sqsh
fi
enroot import -o ${ENROOT_IMAGE}.sqsh dockerd://${ENROOT_IMAGE}:latest
mv ${ENROOT_IMAGE}.sqsh ${IMAGE}