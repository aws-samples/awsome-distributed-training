ARG EFA_INSTALLER_VERSION=1.37.0
ARG AWS_OFI_NCCL_VERSION=v1.13.2-aws
ARG NCCL_VERSION=v2.23.4-1
ARG NCCL_TESTS_VERSION=v2.13.10
FROM public.ecr.aws/hpc-cloud/nccl-tests:efa${EFA_INSTALLER_VERSION}-ofi${AWS_OFI_NCCL_VERSION}-nccl${NCCL_VERSION}-tests${NCCL_TESTS_VERSION}

RUN apt-get update \
    && apt-get install software-properties-common -y \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get install -y python3.10 python3.10-venv python3.10-dev \
    && python3.10 -m venv picotron-venv 

RUN source picotron-venv/bin/activate \
    && git clone https://github.com/huggingface/picotron  \
    && cd picotron \
    && pip install -e .