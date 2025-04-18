FROM 763104351884.dkr.ecr.us-east-1.amazonaws.com/huggingface-pytorch-training-neuronx:2.1.2-transformers4.43.2-neuronx-py310-sdk2.20.0-ubuntu20.04-v1.0

RUN apt-get update && apt-get install -y wget gnupg2 \
    && VERSION_CODENAME=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d= -f2) \
    && echo "deb https://apt.repos.neuron.amazonaws.com ${VERSION_CODENAME} main" | tee /etc/apt/sources.list.d/neuron.list \
    && wget -qO - https://apt.repos.neuron.amazonaws.com/GPG-PUB-KEY-AMAZON-AWS-NEURON.PUB | apt-key add - \
    && apt-get update

RUN apt-get install aws-neuronx-dkms=2.* -y

# Upgrade neuron runtime
RUN apt-get install aws-neuronx-collectives=2.23.135.0-3e70920f2 -y
RUN apt-get install aws-neuronx-runtime-lib=2.23.112.0-9b5179492 -y

# Install Neuron Tools 
RUN apt-get install aws-neuronx-tools=2.20.204.0 -y

# # Set pip repository pointing to the Neuron repository 
RUN python -m pip config set global.extra-index-url https://pip.repos.neuron.amazonaws.com

# # Install wget, awscli 
RUN python -m pip install wget 
RUN python -m pip install awscli 

# # Update Neuron Compiler and Framework
RUN python -m pip install --upgrade neuronx-cc==2.16.372.0 torch-neuronx==2.1.2.2.4.0 torchvision
RUN python -m pip install --upgrade neuronx-distributed==0.10.1 neuronx-distributed-training==1.1.1

RUN mkdir workspace

COPY src/peft_tokenize_data.py workspace/peft_tokenize_data.py
COPY src/peft_train.py workspace/peft_train.py
COPY src/consolidation.py workspace/consolidation.py
COPY src/merge_lora.py workspace/merge_lora.py

RUN python3 -m pip install datasets==2.18.0 tokenizers==0.21.1 peft==0.14.0 huggingface_hub trl==0.11.4 PyYAML accelerate==0.29.2

RUN python3 -m pip install optimum-neuron==0.1.0

WORKDIR /workspace