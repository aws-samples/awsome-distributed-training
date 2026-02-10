FROM public.ecr.aws/hpc-cloud/nccl-tests:latest

RUN apt update && apt install -y nvtop

RUN mkdir -p /fsdp /checkpoints
RUN ln -s /usr/bin/python3 /usr/bin/python

COPY src/ /fsdp/
RUN --mount=type=cache,target=/root/.cache/pip pip install -r /fsdp/requirements.txt
RUN pip install hyperpod-elastic-agent
RUN pip install --force-reinstall torch==2.9.1 torchvision==0.24.1 torchaudio==2.9.1 --index-url https://download.pytorch.org/whl/cu128

WORKDIR /fsdp
