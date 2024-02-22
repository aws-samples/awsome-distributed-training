ARG NEMO_MULTIMODAL_VERSION

FROM nvcr.io/ea-bignlp/ea-mm-participants/bignlp-mm:${NEMO_MULTIMODAL_VERSION}-py3

ARG EFA_INSTALLER_VERSION=latest
ARG AWS_OFI_NCCL_VERSION=v1.7.3-aws
ARG NCCL_TESTS_VERSION=master
ARG NCCL_VERSION=v2.18.5-1
RUN apt-get update -y
RUN apt-get remove -y --allow-change-held-packages \
    libmlx5-1 ibverbs-utils libibverbs-dev libibverbs1 libnccl2 libnccl-dev

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
ENV PATH /opt/amazon/openmpi/bin/:/opt/amazon/efa/bin:/usr/bin:/usr/local/bin:$PATH
RUN curl https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py \
 && python3 /tmp/get-pip.py \
    && pip3 install awscli pynvml

#################################################
# Install NVIDIA GDRCopy
RUN git clone https://github.com/NVIDIA/gdrcopy.git /opt/gdrcopy \
    && cd /opt/gdrcopy \
    && make lib_install install \
    && cd /opt/gdrcopy/tests \
    && make \
    && mv gdrcopy_copylat gdrcopy_copybw gdrcopy_sanity gdrcopy_apiperf /usr/bin/

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
RUN git clone https://github.com/NVIDIA/nccl -b ${NCCL_VERSION} /opt/nccl \
    && cd /opt/nccl \
    && make -j src.build CUDA_HOME=/usr/local/cuda \
    NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_90,code=sm_90"

###################################################
## Install AWS-OFI-NCCL plugin
RUN apt-get install libtool autoconf cmake nasm unzip pigz parallel nfs-common build-essential hwloc libhwloc-dev libjemalloc2 libnuma-dev numactl libjemalloc-dev preload htop iftop liblapack-dev libgfortran5 ipcalc wget curl devscripts debhelper check libsubunit-dev fakeroot pkg-config dkms -y
RUN export OPAL_PREFIX="" \
    && git clone https://github.com/aws/aws-ofi-nccl.git /opt/aws-ofi-nccl \
    && cd /opt/aws-ofi-nccl \
    && git checkout ${AWS_OFI_NCCL_VERSION} \
    && ./autogen.sh \
    && ./configure --prefix=/opt/aws-ofi-nccl/install \
    --with-libfabric=/opt/amazon/efa/ \
    --with-cuda=/usr/local/cuda \
    --with-nccl=/opt/nccl/build \
    --with-mpi=/opt/amazon/openmpi/ \
    && make && make install

###################################################
## Install NCCL-tests
RUN git clone https://github.com/NVIDIA/nccl-tests.git /opt/nccl-tests \
    && cd /opt/nccl-tests \
    && git checkout ${NCCL_TESTS_VERSION} \
    && make MPI=1 \
    MPI_HOME=/opt/amazon/openmpi/ \
    CUDA_HOME=/usr/local/cuda \
    NCCL_HOME=/opt/nccl/build \
    NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_90,code=sm_90"



RUN rm -rf /var/lib/apt/lists/*
ENV LD_PRELOAD /opt/nccl/build/lib/libnccl.so


##############################################
## Nemo-multimodal dependencie
COPY requirements.txt /workspace/
RUN pip3 install -r /workspace/requirements.txt
