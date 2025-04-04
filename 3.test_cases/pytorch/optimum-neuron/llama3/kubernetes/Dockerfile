FROM 763104351884.dkr.ecr.us-east-1.amazonaws.com/huggingface-pytorch-training-neuronx:2.1.2-transformers4.43.2-neuronx-py310-sdk2.20.0-ubuntu20.04-v1.0

RUN mkdir workspace

COPY src/peft_tokenize_data.py workspace/peft_tokenize_data.py
COPY src/peft_train.py workspace/peft_train.py
COPY src/consolidation.py workspace/consolidation.py
COPY src/merge_lora.py workspace/merge_lora.py

RUN python3 -m pip install datasets peft huggingface_hub trl==0.11.4 PyYAML accelerate==0.29.2 optimum-neuron==0.0.26
RUN python3 -m pip install transformers==4.45.0

WORKDIR /workspace