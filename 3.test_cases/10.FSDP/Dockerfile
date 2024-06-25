
FROM public.ecr.aws/hpc-cloud/nccl-tests:latest

RUN apt update && apt install -y nvtop

RUN pip install torchvision torchaudio transformers datasets fsspec==2023.9.2 python-etcd numpy==1.*
RUN pip install torch==2.2.0+cu121 --index-url https://download.pytorch.org/whl/cu121

RUN mkdir /checkpoints

RUN mkdir /fsdp

RUN ln -s /usr/bin/python3 /usr/bin/python

COPY ./train.py /fsdp/train.py

COPY /model_utils /fsdp/model_utils

WORKDIR /fsdp

