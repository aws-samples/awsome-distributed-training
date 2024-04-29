# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

####################################################################################################
# This is a sample Dockerfile, with optional stanzas. Please read through this Dockerfile,
# understand what it does, then create your own Dockerfile.
#
# Sample build instructions:
#
#     docker build --progress=plain -t nvidia-pt-od:latest -f 0.nvcr-pytorch-aws.dockerfile .
#     rm /fsx/nvidia-pt-od__latest.sqsh ; enroot import -o /fsx/nvidia-pt-od__latest.sqsh dockerd://nvidia-pt-od:latest
#
# Compute nodes (aka build nodes) are transient, so we need to keep the docker image on shared fs,
# which head node can load into its local registry.
#
#     # Build node: save image to file
#     docker save nvidia-pt-od:latest > /fsx/nvidia-pt-od__latest.tar
#
#     # Load image to local docker registry -> on head node, or new compute/build node.
#     docker load < /fsx/nvidia-pt-od__latest.tar
####################################################################################################
FROM nvcr.io/nvidia/pytorch:23.12-py3
ENV DEBIAN_FRONTEND=noninteractive

# The three must-be-built packages.
# Efa-installer>=1.29.0 required for nccl>=2.19.0 to avoid libfabric NCCL error.
ENV EFA_INSTALLER_VERSION=1.30.0
ENV AWS_OFI_NCCL_VERSION=1.8.1-aws
ENV NCCL_VERSION=2.20.3-1
ENV NCCL_TESTS_VERSION=master

RUN apt-get update -y
RUN apt-get remove -y --allow-change-held-packages \
                      libmlx5-1 ibverbs-utils libibverbs-dev libibverbs1

# We noticed that since 23.09, we can't just delete the whole /opt/hpcx/, otherwise `import torch`
# complains about missing libuc?.so.
RUN rm -rf /opt/hpcx/ompi \
    && rm -rf /usr/local/mpi \
    && rm -rf /opt/hpcx/nccl_rdma_sharp_plugin \
    && ldconfig
ENV OPAL_PREFIX=
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-unauthenticated \
    git \
    gcc \
    vim \
    kmod \
    openssh-client \
    openssh-server \
    build-essential \
    curl \
    autoconf \
    libtool \
    gdb \
    automake \
    cmake \
    apt-utils \
    libhwloc-dev \
    aptitude && \
    DEBIAN_FRONTEND=noninteractive apt autoremove -y

# EFA
RUN apt-get update && \
    cd /tmp && \
    curl -O https://efa-installer.amazonaws.com/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz  && \
    tar -xf aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz && \
    cd aws-efa-installer && \
    # ONLY add `--skip-kmod`, `--no-verify` and `--skip-limit-conf` flags to container image.
    # Those three flags must NOT be used on the host.
    #
    # Explanations:
    # - to build EFA in the Dockerfile, we added --skip-kmod and --no-verify. Without these flags,
    #   the Dockerfile will fail to build. If installing EFA on the host and not in a container,
    #   please remove these flags.
    # - The --skip-limit-conf can be retained in Dockerfile, but it's redundant as the host already
    #   has these limits set by efa_installer.
    ./efa_installer.sh -y -g -d --skip-kmod --no-verify --skip-limit-conf && \
    ldconfig && \
    rm -rf /tmp/aws-efa-installer /var/lib/apt/lists/*
ENV LD_LIBRARY_PATH=/opt/amazon/efa/lib:$LD_LIBRARY_PATH
ENV PATH=/opt/amazon/efa/bin:/opt/amazon/openmpi/bin:$PATH


####################################################################################################
# [CUSTOM_NCCL_OPTION_1] Uncomment below stanza to install another NCCL version using the official
# binaries.
#
# NCCL EFA plugin (aws-ofi-nccl) depends on mpi, hence we must rebuild openmpi before building the
# aws-ofi-ccnl.
####################################################################################################
#ENV NCCL_VERSION=2.20.3-1
#RUN cd /opt && \
#    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-keyring_1.0-1_all.deb && \
#    dpkg -i cuda-keyring_1.0-1_all.deb && \
#    apt update && \
#    apt install -y libnccl2==${NCCL_VERSION} libnccl-dev==${NCCL_VERSION} && \
#    echo NCCL_SOCKET_IFNAME=^docker0,lo >> /etc/nccl.conf


####################################################################################################
# [CUSTOM_NCCL_OPTION_2] Install NCCL from source to the same location as the built-in ones. The
# benefits of installing to the same location as the built-in version are:
#
# 1. There's only ever a single libnccl version offered by this image, preventing application from
#    mistakenly chooses a wrong version.
# 2. No longer needing extra settings for LD_LIBRARY_PATH or LD_PRELOAD.
#
# NCCL EFA plugin (aws-ofi-nccl) depends on mpi, hence we must rebuild openmpi before building the
# aws-ofi-ccnl.
####################################################################################################
# RUN apt-get remove -y libnccl2 libnccl-dev \
#    && cd /tmp \
#    && git clone https://github.com/NVIDIA/nccl.git -b v${NCCL_VERSION} \
#    && cd nccl \
#    && make -j src.build BUILDDIR=/usr \
#    # Build for p4 & p5.
#    NVCC_GENCODE="-gencode=arch=compute_90,code=sm_90, -gencode=arch=compute_80,code=sm_80" \
#    && rm -rf /tmp/nccl \
#    && echo NCCL_SOCKET_IFNAME=^docker0,lo >> /etc/nccl.conf
# Note: disabled custom NCCL installation as PyTorch container preinstalled 2.19.3 (cf. https://github.com/aws-samples/awsome-distributed-training/pull/174#discussion_r1519045216)
# yet Keeping the above instructions for future updates.

# NCCL EFA Plugin
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
        --enable-platform-aws \
        --with-mpi=/opt/amazon/openmpi && \
    make -j$(nproc) install && \
    rm -rf /tmp/aws-ofi/nccl

# Do this to minimize the ld path env vars that users need to define when running this image.
RUN echo "/usr/local/lib"      >> /etc/ld.so.conf.d/local.conf && \
    echo "/opt/amazon/openmpi/lib" >> /etc/ld.so.conf.d/efa.conf && \
    ldconfig

ENV OMPI_MCA_pml=^cm,ucx            \
    OMPI_MCA_btl=tcp,self           \
    OMPI_MCA_btl_tcp_if_exclude=lo,docker0 \
    OPAL_PREFIX=/opt/amazon/openmpi \
    # https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
    # https://github.com/pytorch/pytorch/issues/68893
    NCCL_SOCKET_IFNAME=^docker,lo

ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"

# NCCL-tests: always good to include this as a diagnostic tool.
RUN git clone https://github.com/NVIDIA/nccl-tests.git /opt/nccl-tests \
    && cd /opt/nccl-tests \
    && git checkout ${NCCL_TESTS_VERSION} \
    && make MPI=1 \
    MPI_HOME=/opt/amazon/openmpi \
    CUDA_HOME=/usr/local/cuda \
    NVCC_GENCODE="-gencode=arch=compute_90,code=sm_90 -gencode=arch=compute_80,code=sm_80"

COPY . /workspace
WORKDIR /workspace/

RUN pip install -r requirements.txt
