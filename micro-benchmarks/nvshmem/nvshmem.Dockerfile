# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
ARG GDRCOPY_VERSION=v2.4.1
ARG EFA_INSTALLER_VERSION=1.37.0
ARG AWS_OFI_NCCL_VERSION=v1.13.2-aws
ARG NCCL_VERSION=v2.23.4-1
ARG NCCL_TESTS_VERSION=v2.13.10

FROM nccl-tests:efa${EFA_INSTALLER_VERSION}-ofi${AWS_OFI_NCCL_VERSION}-nccl${NCCL_VERSION}-tests${NCCL_TESTS_VERSION}

ARG NVSHMEM_VERSION=3.2.5-1

ENV NVSHMEM_DIR=/opt/nvshmem
ENV NVSHMEM_HOME=/opt/nvshmem

RUN curl -L https://developer.nvidia.com/downloads/assets/secure/nvshmem/nvshmem_src_${NVSHMEM_VERSION}.txz -o /nvshmem_src_${NVSHMEM_VERSION}.txz \
    && tar -xf /nvshmem_src_${NVSHMEM_VERSION}.txz -C / \
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
