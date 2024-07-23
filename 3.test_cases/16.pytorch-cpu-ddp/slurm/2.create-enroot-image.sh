#!/usr/bin/env bash
set -ex

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Remove old sqsh file if exists
if [ -f ${ENROOT_IMAGE}.sqsh ] ; then
    rm pytorch.sqsh
fi

enroot import --output pytorch.sqsh docker://pytorch/pytorch