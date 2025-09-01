# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
ARG GDRCOPY_VERSION=v2.5.1
ARG EFA_INSTALLER_VERSION=1.43.2
ARG AWS_OFI_NCCL_VERSION=v1.16.3
ARG NCCL_VERSION=v2.27.7-1
ARG NCCL_TESTS_VERSION=v2.16.9

FROM nccl-tests:efa${EFA_INSTALLER_VERSION}-ofi${AWS_OFI_NCCL_VERSION}-nccl${NCCL_VERSION}-tests${NCCL_TESTS_VERSION}

RUN apt-get update -y && apt-get upgrade -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3.10-dev \
    python3.10-venv

ARG NVSHMEM_VERSION=3.3.9

ENV NVSHMEM_DIR=/opt/nvshmem
ENV NVSHMEM_HOME=/opt/nvshmem

RUN curl -L https://developer.download.nvidia.com/compute/redist/nvshmem/${NVSHMEM_VERSION}/source/nvshmem_src_cuda12-all-all-${NVSHMEM_VERSION}.tar.gz -o /nvshmem_src.txz \
    && tar -xf /nvshmem_src.txz -C / \
    && cd /nvshmem_src \
    && mkdir -p build \
    && cd build \ 
    && cmake \
    -DNVSHMEM_PREFIX=/opt/nvshmem \
    -DCMAKE_INSTALL_PREFIX=/opt/nvshmem \
    \
    -DCUDA_HOME=/usr/local/cuda \
    -DCMAKE_CUDA_ARCHITECTURES=90a \
    \
    -DNVSHMEM_USE_GDRCOPY=1 \
    -DGDRCOPY_HOME=/opt/gdrcopy \
    \
    -DNVSHMEM_USE_NCCL=1 \
    -DNCCL_HOME=/opt/nccl/build \
    -DNCCL_INCLUDE=/opt/nccl/build/include \
    \
    -DNVSHMEM_LIBFABRIC_SUPPORT=1 \
    -DLIBFABRIC_HOME=/opt/amazon/efa \
    \
    -DNVSHMEM_MPI_SUPPORT=1 \
    -DMPI_HOME=/opt/amazon/openmpi \
    \
    -DNVSHMEM_PMIX_SUPPORT=1 \
    -DPMIX_HOME=/opt/amazon/pmix \
    -DNVSHMEM_DEFAULT_PMIX=1 \
    \
    -DNVSHMEM_BUILD_TESTS=1 \
    -DNVSHMEM_BUILD_EXAMPLES=1 \
    -DNVSHMEM_BUILD_HYDRA_LAUNCHER=1 \
    -DNVSHMEM_BUILD_TXZ_PACKAGE=1 \
    \
    -DNVSHMEM_IBRC_SUPPORT=1 \
    -DNVSHMEM_IBGDA_SUPPORT=1 \
    \
    -DNVSHMEM_TIMEOUT_DEVICE_POLLING=0 \
    \
    -DNVSHMEM_DEBUG=WARN \
    -DNVSHMEM_TRACE=1 \
    .. \
    && make -j$(nproc) \
    && make install

ENV PATH=/opt/nvshmem/bin:$PATH LD_LIBRARY_PATH=/opt/amazon/pmix/lib:/opt/nvshmem/lib:$LD_LIBRARY_PATH NVSHMEM_REMOTE_TRANSPORT=libfabric NVSHMEM_LIBFABRIC_PROVIDER=efa
