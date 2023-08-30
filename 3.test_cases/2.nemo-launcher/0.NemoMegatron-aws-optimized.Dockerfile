# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# DOCKER_BUILDKIT=1 docker build --progress plain -t aws-nemo-megatron:latest .
# Customized from: https://github.com/NVIDIA/NeMo-Megatron-Launcher/blob/<VERSION>/csp_tools/aws/Dockerfile

FROM nvcr.io/ea-bignlp/nemofw-training:23.07-py3

ARG DEBIAN_FRONTEND=noninteractive
ENV EFA_INSTALLER_VERSION=latest
ENV NCCL_VERSION=inc_nsteps
ENV AWS_OFI_NCCL_VERSION=1.4.0-aws

# Install AWS NCCL
RUN cd /tmp \
    && git clone https://github.com/NVIDIA/nccl.git -b ${NCCL_VERSION} \
    && cd nccl \
    && make -j src.build BUILDDIR=/usr/local \
    # nvcc to target p4 instances
    NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80" \
    && rm -rf /tmp/nccl

# EFA
RUN apt-get update && \
    cd /tmp && \
    curl -O https://efa-installer.amazonaws.com/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz  && \
    tar -xf aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz && \
    cd aws-efa-installer && \
    ./efa_installer.sh -y -g -d --skip-kmod --skip-limit-conf && \
    ldconfig && \
    rm -rf /tmp/aws-efa-installer /var/lib/apt/lists/* && \
    /opt/amazon/efa/bin/fi_info --version

ENV LD_LIBRARY_PATH=/opt/amazon/efa/lib:$LD_LIBRARY_PATH
ENV PATH=/opt/amazon/efa/bin:$PATH

# NCCL EFA Plugin (Dockefile original)
# NOTE: Stick to this version! Otherwise, will get 'ncclInternalError: Internal check failed.'
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
RUN echo "/usr/local/lib"      >> /etc/ld.so.conf.d/local.conf && \
    echo "/opt/amazon/efa/lib" >> /etc/ld.so.conf.d/efa.conf &&  \
    ldconfig

ENV OMPI_MCA_pml=^ucx                \
    OMPI_MCA_btl=^openib,uct

ENV RDMAV_FORK_SAFE=1             \
    FI_PROVIDER=efa               \
    FI_EFA_USE_DEVICE_RDMA=1      \
    NCCL_PROTO=simple

ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib"
