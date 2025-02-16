
FROM public.ecr.aws/hpc-cloud/nccl-tests:latest

RUN apt update && apt install -y nvtop

RUN pip install transformers==4.46.1 datasets fsspec==2023.9.2 python-etcd numpy==1.*
RUN pip install torch==2.5.1+cu121 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

RUN mkdir /checkpoints

RUN mkdir /fsdp

RUN ln -s /usr/bin/python3 /usr/bin/python

COPY ./train.py /fsdp/train.py

COPY /model_utils /fsdp/model_utils

WORKDIR /fsdp

