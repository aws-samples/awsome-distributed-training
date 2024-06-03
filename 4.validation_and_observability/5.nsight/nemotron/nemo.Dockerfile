# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# DOCKER_BUILDKIT=1 docker build --progress plain -t aws-nemo-megatron:latest .

#FROM nvcr.io/ea-bignlp/ga-participants/nemofw-training:23.11

FROM nvcr.io/nvidia/nemo:24.01.framework

ENV DEBIAN_FRONTEND=noninteractive
ARG EFA_INSTALLER_VERSION=1.30.0
ARG AWS_OFI_NCCL_VERSION=v1.8.1-aws
ARG NCCL_VERSION=2.20.3

ARG GDRCOPY_VERSION=2.4.1

RUN apt-get update -y
RUN apt-get remove -y --allow-change-held-packages \
    libmlx5-1 ibverbs-utils libibverbs-dev libibverbs1 libnccl2 libnccl-dev

# Remove existing MPI
# RUN rm -rf /opt/hpcx \
#     && rm -rf /usr/local/mpi \
#     && rm -f /etc/ld.so.conf.d/hpcx.conf \
#     && ldconfig
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
    python3-distutils \
    cmake \
    apt-utils \
    devscripts \
    debhelper \
    libsubunit-dev \
    check \
    pkg-config

RUN mkdir -p /var/run/sshd
RUN sed -i 's/[ #]\(.*StrictHostKeyChecking \).*/ \1no/g' /etc/ssh/ssh_config && \
    echo "    UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config && \
    sed -i 's/#\(StrictModes \).*/\1no/g' /etc/ssh/sshd_config

ENV LD_LIBRARY_PATH /usr/local/cuda/extras/CUPTI/lib64:/opt/amazon/openmpi/lib:/opt/nccl/build/lib:/opt/amazon/efa/lib:/opt/aws-ofi-nccl/install/lib:/usr/local/lib:$LD_LIBRARY_PATH


RUN curl https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py \
    && python3 /tmp/get-pip.py \
    && pip3 install awscli pynvml

#################################################
## Install NVIDIA GDRCopy
RUN git clone -b v${GDRCOPY_VERSION} https://github.com/NVIDIA/gdrcopy.git /tmp/gdrcopy \
   && cd /tmp/gdrcopy \
   && make lib_install install

#################################################
## Install EFA installer
RUN cd $HOME \
    && curl -O https://efa-installer.amazonaws.com/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && tar -xf $HOME/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && cd aws-efa-installer \
    && ./efa_installer.sh -y -g -d --skip-kmod --skip-limit-conf --no-verify \
    && rm -rf $HOME/aws-efa-installer

ENV PATH /opt/amazon/openmpi/bin/:/opt/amazon/efa/bin:/usr/bin:/usr/local/bin:$PATH

###################################################
## Install NCCL
RUN git clone -b v${NCCL_VERSION}-1 https://github.com/NVIDIA/nccl.git /opt/nccl \
    && cd /opt/nccl \
    && make -j src.build CUDA_HOME=/usr/local/cuda \
    NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_90,code=sm_90"

###################################################
## Install AWS-OFI-NCCL plugin
RUN apt-get install libtool autoconf cmake nasm unzip pigz parallel nfs-common build-essential hwloc libhwloc-dev libjemalloc2 libnuma-dev numactl libjemalloc-dev preload htop iftop liblapack-dev libgfortran5 ipcalc wget curl devscripts debhelper check libsubunit-dev fakeroot pkg-config dkms -y
RUN export OPAL_PREFIX="" \
    && git clone -b ${AWS_OFI_NCCL_VERSION} https://github.com/aws/aws-ofi-nccl.git /opt/aws-ofi-nccl \
    && cd /opt/aws-ofi-nccl \
    && ./autogen.sh \
    && ./configure --prefix=/opt/aws-ofi-nccl/install \
        --with-mpi=/opt/amazon/openmpi \
        --with-libfabric=/opt/amazon/efa \
        --with-cuda=/usr/local/cuda \
        --enable-platform-aws \
    && make && make install


ENV OMPI_MCA_pml=^cm,ucx            \
    OMPI_MCA_btl=tcp,self           \
    OMPI_MCA_btl_tcp_if_exclude=lo,docker0,veth_def_agent\
    OPAL_PREFIX=/opt/amazon/openmpi \
    NCCL_SOCKET_IFNAME=^docker,lo
ENV PMIX_MCA_gds=hash

RUN rm -rf /var/lib/apt/lists/*
ENV LD_PRELOAD /opt/nccl/build/lib/libnccl.so
ENV LD_LIBRARY_PATH /opt/hpcx/ucx/lib:$LD_LIBRARY_PATH