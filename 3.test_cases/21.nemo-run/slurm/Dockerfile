FROM nvcr.io/nvidia/nemo:24.12
ENV DEBIAN_FRONTEND=noninteractive

ENV GDRCOPY_VERSION=v2.4.1
ENV EFA_INSTALLER_VERSION=1.37.0
ENV AWS_OFI_NCCL_VERSION=1.13.2-aws
ENV NCCL_VERSION=2.23.4-1
ENV NCCL_TESTS_VERSION=v2.13.10

RUN apt-get update -y
RUN apt-get remove -y --allow-change-held-packages \
    libmlx5-1 ibverbs-utils libibverbs-dev libibverbs1

RUN rm -rf /opt/hpcx/ompi \
    && rm -rf /usr/local/mpi \
    && rm -rf /opt/hpcx/nccl_rdma_sharp_plugin \
    && ldconfig

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
    ./efa_installer.sh -y -g -d --skip-kmod --no-verify --skip-limit-conf && \
    ldconfig && \
    rm -rf /tmp/aws-efa-installer /var/lib/apt/lists/*
ENV LD_LIBRARY_PATH=/opt/amazon/efa/lib:$LD_LIBRARY_PATH
ENV PATH=/opt/amazon/efa/bin:/opt/amazon/openmpi/bin:$PATH

# [CUSTOM_NCCL_OPTION_2] Install NCCL from source to the same location as the built-in ones.
RUN apt-get remove -y libnccl2 libnccl-dev \
   && cd /tmp \
   && git clone https://github.com/NVIDIA/nccl.git -b v${NCCL_VERSION} \
   && cd nccl \
   && make -j src.build BUILDDIR=/usr \
   # Build for p4 & p5.
   NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_90,code=sm_90" \
   && rm -rf /tmp/nccl \
   && echo NCCL_SOCKET_IFNAME=^docker0,lo >> /etc/nccl.conf

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
    OMPI_MCA_btl_tcp_if_exclude=lo,docker0,veth_def_agent \
    OPAL_PREFIX=/opt/amazon/openmpi \
    # https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
    # https://github.com/pytorch/pytorch/issues/68893
    NCCL_SOCKET_IFNAME=^docker,lo,veth

ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"

# NCCL-tests: always good to include this as a diagnostic tool.
RUN git clone https://github.com/NVIDIA/nccl-tests.git /opt/nccl-tests \
    && cd /opt/nccl-tests \
    && git checkout ${NCCL_TESTS_VERSION} \
    && make MPI=1 \
    MPI_HOME=/opt/amazon/openmpi \
    CUDA_HOME=/usr/local/cuda \
    NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_90,code=sm_90"
