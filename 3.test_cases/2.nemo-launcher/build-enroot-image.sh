#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

REPO=aws-nemo-megatron
TAG=23.07-py3

# EC2 instance: us-west-2, EBS: gp3, 3k IOPS, 350 MB/s throughput.
# Time: ~3min
#/usr/bin/time docker pull nvcr.io/ea-bignlp/nemofw-training:$TAG

# EC2 instance: m5.4xlarge, EBS: gp3, 3k IOPS, 350 MB/s throughput.
# Time: ~6min
docker build --progress plain -t ${REPO}:${TAG} -f 0.NemoMegatron-aws-optimized.Dockerfile .

# On m5.8xlarge (32 vcpu). /fsx is FSxL 1.2TB configured with 500 MB/s/TB throughput.
IMAGE=/apps/${REPO}_${TAG}.sqsh ; [[ -e $IMAGE ]] && rm $IMAGE
/usr/bin/time enroot import -o $IMAGE dockerd://${REPO}:${TAG}
# 25.09user 102.21system 2:17.85elapsed 92%CPU (0avgtext+0avgdata 17450056maxresident)k
