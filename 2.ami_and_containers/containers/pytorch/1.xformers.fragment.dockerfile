# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

####################################################################################################
# This is NOT a complete Dockerfile! Attempt to docker build this file is guaranteed to fail.
#
# This file provides an sample stanza to build xformers, that you can optionally add to
# 0.nvcr-pytorch-aws.dockerfile should you need a container image with xformers.
#
# NOTE: always check `pip list` what's been installed. The base container (specified in
# 0.nvcr-pytorch-aws.dockerfile) is already pre-installed with Transformer Engine, flash attention,
# triton (https://github.com/openai/triton/), etc.
####################################################################################################

# Install the xformers dependency from source, because pip install either breaks or try to pull
# its own pt + cuda.
#
# Pre-requisite: build node has enough memory to compile xformers. More info on the stanza.
RUN export TORCH_CUDA_ARCH_LIST="8.0;9.0+PTX" && \
    # On p4de.24xlarge:
    # - MAX_JOBS=16 => 145GB memory
    # - MAX_JOBS=32 => 241GB memory
    # - MAX_JOBS=48 => 243GB memory, 542.5s
    #
    # NOTE: must export MAX_JOBS. For some reason, `MAX_JOBS=16 pip install ...` doesn't seem to
    #       work to prevent OOM.
    export MAX_JOBS=32 && \
    export NVCC_PREPEND_FLAGS="-t 32" && \
    pip install -v -U git+https://github.com/facebookresearch/xformers.git@main#egg=xformers
