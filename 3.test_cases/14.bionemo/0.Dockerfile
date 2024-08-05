FROM nvcr.io/nvidia/clara/bionemo-framework:1.7

ARG EFA_INSTALLER_VERSION=1.33.0
ARG AWS_OFI_NCCL_VERSION=v1.9.2-aws
ARG GDRCOPY_VERSION=v2.4.1
ARG NCCL_TESTS_VERSION=master
ARG NCCL_VERSION=v2.21.5-1

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
ENV LD_LIBRARY_PATH=/usr/local/cuda/extras/CUPTI/lib64:/opt/amazon/openmpi/lib:/opt/nccl/build/lib:/opt/amazon/efa/lib:/opt/aws-ofi-nccl/install/lib:/usr/local/lib:$LD_LIBRARY_PATH
ENV PATH=/opt/amazon/openmpi/bin/:/opt/amazon/efa/bin:/usr/bin:/usr/local/bin:$PATH
RUN curl https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py \
    && python3 /tmp/get-pip.py \
    && pip3 install awscli pynvml

#################################################
## Install NVIDIA GDRCopy
##
## NOTE: if `nccl-tests` or `/opt/gdrcopy/bin/sanity -v` crashes with incompatible version, ensure
## that the cuda-compat-xx-x package is the latest.
RUN git clone -b ${GDRCOPY_VERSION} https://github.com/NVIDIA/gdrcopy.git /tmp/gdrcopy \
    && cd /tmp/gdrcopy \
    && make prefix=/opt/gdrcopy install

ENV LD_LIBRARY_PATH=/opt/gdrcopy/lib:/usr/local/cuda/compat:$LD_LIBRARY_PATH
ENV LIBRARY_PATH=/opt/gdrcopy/lib:/usr/local/cuda/compat/:$LIBRARY_PATH
ENV CPATH=/opt/gdrcopy/include:$CPATH
ENV PATH=/opt/gdrcopy/bin:$PATH

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
RUN git clone -b ${NCCL_VERSION} https://github.com/NVIDIA/nccl.git  /opt/nccl \
    && cd /opt/nccl \
    && make -j $(nproc) src.build CUDA_HOME=/usr/local/cuda \
    NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_89,code=sm_89 -gencode=arch=compute_90,code=sm_90"


###################################################
## Install AWS-OFI-NCCL plugin
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y libhwloc-dev
#Switch from sh to bash to allow parameter expansion
SHELL ["/bin/bash", "-c"]
RUN curl -OL https://github.com/aws/aws-ofi-nccl/releases/download/${AWS_OFI_NCCL_VERSION}/aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v}.tar.gz \
    && tar -xf aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v}.tar.gz \
    && cd aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v} \
    && ./configure --prefix=/opt/aws-ofi-nccl/install \
        --with-mpi=/opt/amazon/openmpi \
        --with-libfabric=/opt/amazon/efa \
        --with-cuda=/usr/local/cuda \
        --enable-platform-aws \
    && make -j $(nproc) \
    && make install \
    && cd .. \
    && rm -rf aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v} \
    && rm aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v}.tar.gz

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


##############################################
COPY prepare_uniref50.py /workspace/bionemo

WORKDIR /workspace/bionemo/