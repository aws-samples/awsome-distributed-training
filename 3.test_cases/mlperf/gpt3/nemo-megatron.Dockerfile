# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# DOCKER_BUILDKIT=1 docker build --progress plain -t aws-nemo-megatron:latest .

#FROM nvcr.io/nvidia/pytorch:24.09-py3
FROM nvcr.io/nvidia/pytorch:24.10-py3

ENV DEBIAN_FRONTEND=noninteractive
ENV EFA_INSTALLER_VERSION=latest
ENV AWS_OFI_NCCL_VERSION=v1.13.2-aws
ENV NCCL_TESTS_VERSION=master

RUN apt-get update -y
RUN apt-get remove -y --allow-change-held-packages \
                      libmlx5-1 ibverbs-utils libibverbs-dev libibverbs1

RUN rm -rf /opt/hpcx/ompi \
    && rm -rf /usr/local/mpi \
    && rm -fr /opt/hpcx/nccl_rdma_sharp_plugin \
    && ldconfig
ENV OPAL_PREFIX=
RUN apt-get install -y --allow-unauthenticated \
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
    apt autoremove -y

# Uncomment below stanza to install the latest NCCL
# Require efa-installer>=1.29.0 for nccl-2.19.0 to avoid libfabric gave NCCL error.
ENV NCCL_VERSION=v2.23.4-1
RUN apt-get remove -y libnccl2 libnccl-dev \
   && cd /tmp \
   && git clone https://github.com/NVIDIA/nccl.git -b ${NCCL_VERSION} \
   && cd nccl \
   && make -j src.build BUILDDIR=/usr/local \
   # nvcc to target p5 and p4 instances
   NVCC_GENCODE="-gencode=arch=compute_90,code=sm_90 -gencode=arch=compute_80,code=sm_80" \
   && rm -rf /tmp/nccl

# EFA
RUN apt-get update && \
    apt-get install -y libhwloc-dev && \
    cd /tmp && \
    curl -O https://efa-installer.amazonaws.com/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz  && \
    tar -xf aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz && \
    cd aws-efa-installer && \
    ./efa_installer.sh -y -g -d --skip-kmod --skip-limit-conf --no-verify && \
    ldconfig && \
    rm -rf /tmp/aws-efa-installer /var/lib/apt/lists/*

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

SHELL ["/bin/sh", "-c"]

# NCCL
RUN echo "/usr/local/lib"      >> /etc/ld.so.conf.d/local.conf && \
    echo "/opt/amazon/openmpi/lib" >> /etc/ld.so.conf.d/efa.conf && \
    ldconfig

ENV OMPI_MCA_pml=^cm,ucx            \
    OMPI_MCA_btl=tcp,self           \
    OMPI_MCA_btl_tcp_if_exclude=lo,docker0 \
    OPAL_PREFIX=/opt/amazon/openmpi \
    NCCL_SOCKET_IFNAME=^docker,lo

# NCCL-tests
RUN git clone https://github.com/NVIDIA/nccl-tests.git /opt/nccl-tests \
    && cd /opt/nccl-tests \
    && git checkout ${NCCL_TESTS_VERSION} \
    && make MPI=1 \
    MPI_HOME=/opt/amazon/openmpi \
    CUDA_HOME=/usr/local/cuda \
    # nvcc to target p5 and p4 instances
    NVCC_GENCODE="-gencode=arch=compute_90,code=sm_90 -gencode=arch=compute_80,code=sm_80"

# Custom libraries version
WORKDIR /workspace/

ARG GIT_COMMIT_ID
ENV GIT_COMMIT_ID=$GIT_COMMIT_ID

## 1. Apex
ARG APEX_REVISION=SKIP
ENV CUSTOM_APEX_REVISION ${APEX_REVISION}
ARG APEX_MAX_JOBS=4
RUN if [ "${APEX_REVISION}" != SKIP ]; then \
      git clone https://github.com/NVIDIA/apex && \
      cd apex && \
      echo APEX_REVISION=${APEX_REVISION} && \
      git checkout ${APEX_REVISION} && \
      echo APEX_COMMIT_HASH=$(git rev-parse HEAD) && \
      MAX_JOBS=${APEX_MAX_JOBS} NVCC_APPEND_FLAGS="--threads 8" pip install -v --no-build-isolation --no-cache-dir --disable-pip-version-check --config-settings "--build-option=--cpp_ext --cuda_ext --bnp --xentropy --deprecated_fused_adam --deprecated_fused_lamb --fast_multihead_attn --distributed_lamb --fast_layer_norm --transducer --distributed_adam --fmha --fast_bottleneck --nccl_p2p --peer_memory --permutation_search --focal_loss --fused_conv_bias_relu --index_mul_2d --cudnn_gbn --group_norm" . \
    ; fi

## 2. Transformer Engine
ARG TE_REVISION=v1.10
ENV CUSTOM_TE_REVISION ${TE_REVISION}
RUN if [ "${TE_REVISION}" != SKIP ]; then \
      NVTE_UB_WITH_MPI=1 MPI_HOME=/opt/amazon/openmpi pip install --force-reinstall --no-deps git+https://github.com/NVIDIA/TransformerEngine.git@${TE_REVISION} \
    ; fi

## 3. NeMo
ARG NEMO_REVISION=24.09-alpha.rc0
ENV CUSTOM_NEMO_REVISION ${NEMO_REVISION}
ARG NEMO_BASE_VERSION=r2.0.0
ENV CUSTOM_NEMO_BASE_VERSION ${NEMO_BASE_VERSION}
RUN git clone https://github.com/NVIDIA/NeMo.git && \
    cd NeMo && \
    git config user.email "email@email.com" && \
    git config user.name "name name" && \
    git checkout ${NEMO_REVISION} && \
    pip uninstall -y nemo-toolkit sacrebleu && \
    pip install "cython<3.0.0" && \
    pip install -e ".[nlp]" && \
    cd nemo/collections/nlp/data/language_modeling/megatron && \
    make


# 4. Megatron-core
ARG MEGATRON_REVISION=24.09-alpha.rc0
ENV CUSTOM_MEGATRON_REVISION ${MEGATRON_REVISION}

RUN if [ "${MEGATRON_REVISION}" != SKIP ]; then \
      pip uninstall -y megatron-core && \
      git clone https://github.com/NVIDIA/Megatron-LM && \
      cd Megatron-LM && \
      git config user.email "docker@dummy.com" && \
      git config user.name "Docker Build" && \
      git checkout ${CUSTOM_MEGATRON_REVISION} && \
      echo MEGATRON_COMMIT_HASH=$(git rev-parse HEAD) && \
      pip install . && \
      cd megatron/core/datasets && \
      make \
    ; fi

ENV PYTHONPATH "${PYTHONPATH}:/workspace/Megatron-LM"


## 5. Benchmark dependencies
RUN pip install --no-cache-dir git+https://github.com/mlcommons/logging.git@4.1.0-rc3
RUN pip install --no-cache-dir git+https://github.com/NVIDIA/mlperf-common.git@training-v4.1-rc0

# Fix HF and pkg_resources import issues (remove after it is fixed)
RUN pip install -U huggingface_hub
RUN pip install setuptools==69.5.1
RUN pip install pytorch-lightning==2.4.0
#RUN git clone https://github.com/mlperf/logging.git mlperf-logging
#RUN pip install -e mlperf-logging

## fix opencc
RUN apt-get update && apt-get install -y --no-install-recommends libopencc-dev

# Benchmark code
WORKDIR /workspace/llm

COPY . .
ENV PYTHONPATH "/workspace/llm:/workspace/NeMo:${PYTHONPATH}"
