FROM 763104351884.dkr.ecr.us-east-2.amazonaws.com/pytorch-training-neuronx:2.1.2-neuronx-py310-sdk2.19.1-ubuntu20.04

COPY ./src /workspace
COPY ./config_8b_llama3.1 workspace/config_8b_llama3.1
COPY ./config_8b_llama3 workspace/config_8b_llama3

WORKDIR /workspace

RUN pip install -r requirements.txt