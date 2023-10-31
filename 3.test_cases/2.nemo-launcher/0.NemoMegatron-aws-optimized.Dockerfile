# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# DOCKER_BUILDKIT=1 docker build --progress plain -t aws-nemo-megatron:latest .
# Customized from: https://github.com/NVIDIA/NeMo-Megatron-Launcher/blob/<VERSION>/csp_tools/aws/Dockerfile

FROM nvcr.io/ea-bignlp/ga-participants/nemofw-training:23.08.03

ARG DEBIAN_FRONTEND=noninteractive
ENV EFA_INSTALLER_VERSION=1.28.0
ENV NCCL_VERSION=2.18.5-1+cuda12.2
ENV AWS_OFI_NCCL_VERSION=1.7.3-aws


RUN apt-get update -y \
    && apt-get remove -y --allow-change-held-packages \
                       libmlx5-1 ibverbs-utils libibverbs-dev libibverbs1 \
    && rm -rf /opt/hpcx/ompi \
    && rm -rf /usr/local/mpi \
    && rm -rf /usr/local/ucx \
    && ldconfig

RUN  echo "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64 /" >> //etc/apt/sources.list.d/cuda.list \
     && curl https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub > /tmp/3bf863cc.pub \
     && echo "34bb9f7e66744d7b2944d0565db6687560d5d6e3 /tmp/3bf863cc.pub" | sha1sum --check \
     && apt-key add /tmp/3bf863cc.pub \
     && unlink /tmp/3bf863cc.pub \
     && apt-get update -y \
     && apt-get install -y libnccl2=${NCCL_VERSION} libnccl-dev=${NCCL_VERSION} \
     && apt-get clean


# EFA
RUN apt-get update && \
    apt-get install -y libhwloc-dev && \
    cd /tmp && \
    curl -O https://efa-installer.amazonaws.com/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz  && \
    tar -xf aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz && \
    cd aws-efa-installer && \
    ./efa_installer.sh -y -g -d --skip-kmod --skip-limit-conf --no-verify && \
    ldconfig && \
    rm -rf /tmp/aws-efa-installer /var/lib/apt/lists/* && \
    apt-get clean && \
    /opt/amazon/efa/bin/fi_info --version

ENV LD_LIBRARY_PATH=/opt/amazon/openmpi/lib:/opt/amazon/efa/lib:$LD_LIBRARY_PATH
ENV PATH=/opt/amazon/openmpi/bin/:/opt/amazon/efa/bin:$PATH

# NCCL EFA Plugin (Dockefile original)
# NOTE: Stick to this version! Otherwise, will get 'ncclInternalError: Internal check failed.'
RUN apt-get update -y \
    && apt-get install -y libhwloc-dev

RUN mkdir -p /tmp && \
    cd /tmp && \
    curl -LO https://github.com/aws/aws-ofi-nccl/archive/refs/tags/v${AWS_OFI_NCCL_VERSION}.tar.gz && \
    tar -xzf /tmp/v${AWS_OFI_NCCL_VERSION}.tar.gz && \
    rm /tmp/v${AWS_OFI_NCCL_VERSION}.tar.gz && \
    mv aws-ofi-nccl-${AWS_OFI_NCCL_VERSION} aws-ofi-nccl && \
    cd /tmp/aws-ofi-nccl && \
    ./autogen.sh && \
    ./configure --prefix=/opt/amazon/efa \
        --with-libfabric=/opt/amazon/efa \
        --with-cuda=/usr/local/cuda \
        --with-mpi=/usr/local/mpi && \
    make -j$(nproc) install && \
    rm -rf /tmp/aws-ofi/nccl

# NCCL
RUN echo "/opt/amazon/efa/lib" >> /etc/ld.so.conf.d/efa.conf &&  \
    ldconfig

ENV OMPI_MCA_pml=^ucx                \
    OMPI_MCA_btl=^openib,uct

ENV RDMAV_FORK_SAFE=1             \
    FI_PROVIDER=efa               \
    FI_EFA_USE_DEVICE_RDMA=1      \
    NCCL_PROTO=simple

ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib"
