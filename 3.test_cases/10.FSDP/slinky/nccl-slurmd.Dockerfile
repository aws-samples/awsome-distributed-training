# First stage - NCCL and CUDA environment
FROM public.ecr.aws/hpc-cloud/nccl-tests:latest AS nccl
RUN find / -name nccl.h

# Second stage - Slurm compute node with NCCL capabilities
FROM ghcr.io/slinkyproject/slurmd:24.05.7-ubuntu24.04

# Install Python and pip
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy NCCL and CUDA related files from the first stage
COPY --from=nccl /usr/local/cuda /usr/local/cuda
COPY --from=nccl /opt/nccl/build/lib/libnccl* /usr/lib/x86_64-linux-gnu/
COPY --from=nccl /opt/nccl/build/include/nccl.h /usr/include/
COPY --from=nccl /opt/amazon/efa /opt/amazon/efa
COPY --from=nccl /opt/aws-ofi-nccl /opt/aws-ofi-nccl

# Set environment variables
ENV CUDA_HOME=/usr/local/cuda
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu:/opt/amazon/efa/lib64:/opt/aws-ofi-nccl/lib
ENV PATH=$PATH:/usr/local/cuda/bin
ENV NCCL_DEBUG=INFO
ENV FI_PROVIDER=efa
ENV FI_EFA_USE_HUGE_PAGE=0
ENV FI_EFA_SET_CUDA_SYNC_MEMOPS=0
ENV NCCL_SOCKET_IFNAME='^docker,lo,veth_def_agent,eth'

WORKDIR /shared
