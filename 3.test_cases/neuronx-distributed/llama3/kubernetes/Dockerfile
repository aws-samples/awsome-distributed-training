FROM 763104351884.dkr.ecr.us-east-2.amazonaws.com/pytorch-training-neuronx:2.1.2-neuronx-py310-sdk2.19.1-ubuntu20.04

RUN git clone https://github.com/aws-neuron/neuronx-distributed.git
COPY ./src /workspace
RUN cp -r neuronx-distributed/examples/training/llama/tp_zero1_llama_hf_pretrain/8B_config_llama3.1 workspace/config_8b_llama3.1
RUN cp -r neuronx-distributed/examples/training/llama/tp_zero1_llama_hf_pretrain/8B_config_llama3 workspace/config_8b_llama3

WORKDIR /workspace

RUN pip install -r requirements.txt