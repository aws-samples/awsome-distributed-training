FROM nvcr.io/nvidia/tensorflow:23.10-tf2-py3

ARG EFA_INSTALLER_VERSION=1.30.0
ARG AWS_OFI_NCCL_VERSION=v1.7.4-aws
ARG NCCL_TESTS_VERSION=master
ARG NCCL_VERSION=v2.18.6-1
ARG OPEN_MPI_PATH=/opt/amazon/openmpi

RUN apt-get update -y
RUN apt-get remove -y --allow-change-held-packages \
    libmlx5-1 ibverbs-utils libibverbs-dev libibverbs1 \
    libnccl2 libnccl-dev libibnetdisc5 libibmad5 libibumad3
RUN rm -rf /opt/hpcx \
    && rm -rf /usr/local/mpi \
    && rm -rf /usr/local/ucx \
    && rm -f /etc/ld.so.conf.d/hpcx.conf \
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
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/:/usr/local/cuda/extras/CUPTI/lib64:/opt/amazon/openmpi/lib:/opt/nccl/build/lib:/opt/amazon/efa/lib:/opt/aws-ofi-nccl/install/lib:$LD_LIBRARY_PATH
ENV PATH=/opt/amazon/openmpi/bin/:/opt/amazon/efa/bin:/usr/bin:/usr/local/bin:$PATH

RUN pip install awscli pynvml

#################################################
## Install EFA installer
RUN cd $HOME \
    && curl -O https://efa-installer.amazonaws.com/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && tar -xf $HOME/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && cd aws-efa-installer \
    && ./efa_installer.sh -y -g -d --skip-kmod --skip-limit-conf --no-verify \
    && rm -rf $HOME/aws-efa-installer

###################################################
## Install NCCL
RUN cd /tmp \
    && git clone https://github.com/NVIDIA/nccl.git -b v${NCCL_VERSION} \
    && cd nccl \
    && make -j src.build BUILDDIR=/usr/local \
    # nvcc to target p5 and p4 instances
    NVCC_GENCODE="-gencode=arch=compute_90,code=sm_90 -gencode=arch=compute_80,code=sm_80" \
    && rm -rf /tmp/nccl

# NCCL
RUN echo "/usr/local/lib"      >> /etc/ld.so.conf.d/local.conf && \
    echo "/opt/amazon/efa/lib" >> /etc/ld.so.conf.d/efa.conf &&  \
    echo "/opt/amazon/openmpi/lib" >> /etc/ld.so.conf.d/efa.conf && \
    ldconfig

###################################################
## Install AWS-OFI-NCCL plugin
RUN export OPAL_PREFIX="" \
    && git clone https://github.com/aws/aws-ofi-nccl.git /opt/aws-ofi-nccl \
    && cd /opt/aws-ofi-nccl \
    && git checkout ${AWS_OFI_NCCL_VERSION} \
    && ./autogen.sh \
    && ./configure --prefix=/opt/aws-ofi-nccl/install \
    --with-libfabric=/opt/amazon/efa/ \
    --with-cuda=/usr/local/cuda \
    --with-nccl=/usr/local/nccl \
    --with-mpi=/opt/amazon/openmpi/ \
    && make -j && make install

RUN rm -rf /var/lib/apt/lists/*

RUN echo "hwloc_base_binding_policy = none" >> /opt/amazon/openmpi/etc/openmpi-mca-params.conf \
    && echo "rmaps_base_mapping_policy = slot" >> /opt/amazon/openmpi/etc/openmpi-mca-params.conf

COPY src /src
