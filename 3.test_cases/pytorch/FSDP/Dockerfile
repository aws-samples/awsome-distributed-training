
FROM public.ecr.aws/hpc-cloud/nccl-tests:latest

RUN apt update && apt install -y nvtop

RUN mkdir -p /fsdp /checkpoints
RUN ln -s /usr/bin/python3 /usr/bin/python

COPY src/ /fsdp/
RUN pip install -r /fsdp/requirements.txt

WORKDIR /fsdp

