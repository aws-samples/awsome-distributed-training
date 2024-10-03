# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

####################################################################################################
# This is NOT a complete Dockerfile! Attempt to docker build this file is guaranteed to fail.
#
# This file provides an sample stanza to rebuild OpenMPI with custom PMIX version. E.g., to match
# what host's Slurm is built with (see /opt/pmix/ on host, or run pmix_info on host).
#
# You might need this only on rare occassions when `srun --mpi=pmix --container-image=... <mpi_app>`
# mysteriously crashes.
#
# NCCL EFA plugin (aws-ofi-nccl) depends on mpi, hence we must rebuild openmpi **BEFORE** we build
# the aws-ofi-ccnl.
####################################################################################################

ENV OPEN_MPI_PATH=/opt/amazon/openmpi

# OpenMPI build script claims PMIX_VERSION, and complains if we use it.
ENV CUSTOM_PMIX_VERSION=4.2.7
RUN apt-get update && apt-get install -y libevent-dev \
    && cd /tmp \
    && wget https://github.com/openpmix/openpmix/releases/download/v${CUSTOM_PMIX_VERSION}/pmix-${CUSTOM_PMIX_VERSION}.tar.gz \
    && tar -xzf pmix-${CUSTOM_PMIX_VERSION}.tar.gz \
    && rm pmix-${CUSTOM_PMIX_VERSION}.tar.gz \
    && cd pmix-${CUSTOM_PMIX_VERSION}/ \
    && ./autogen.pl \
    && ./configure --prefix=/opt/pmix \
    && make -j \
    && make install \
    && echo /opt/pmix/lib > /etc/ld.so.conf.d/pmix.conf \
    && ldconfig \
    && cd / \
    && rm -fr /tmp/pmix-${CUSTOM_PMIX_VERSION}/

# Rebuild openmpi with DLC style (which it remarks as "without libfabric"), with the above pmix.
ENV OMPI_VERSION=4.1.6
RUN rm -fr ${OPEN_MPI_PATH} \
 && mkdir /tmp/openmpi \
 && cd /tmp/openmpi \
 && wget --quiet https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-${OMPI_VERSION}.tar.gz \
 && tar zxf openmpi-${OMPI_VERSION}.tar.gz \
 && rm openmpi-${OMPI_VERSION}.tar.gz \
 && cd openmpi-${OMPI_VERSION} \
 && ./configure --enable-orterun-prefix-by-default --prefix=$OPEN_MPI_PATH --with-cuda=${CUDA_HOME} --with-slurm --with-pmix=/opt/pmix \
 && make -j $(nproc) all \
 && make install \
 && ldconfig \
 && cd / \
 && rm -rf /tmp/openmpi \
 && ompi_info --parsable --all | grep mpi_built_with_cuda_support:value \
 # Verify pmix from /opt/pmix/
 && ldd /opt/amazon/openmpi/lib/openmpi/mca_pmix_ext3x.so | grep '/opt/pmix/lib/libpmix.so.* ' > /opt/amazon/openmpi-pmix.txt
