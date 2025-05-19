FROM public.ecr.aws/hpc-cloud/nccl-tests:latest

# Install Miniconda to not depend on the base image python
RUN mkdir -p /opt/miniconda3 \
    && curl -L https://repo.anaconda.com/miniconda/Miniconda3-py312_25.3.1-1-Linux-x86_64.sh -o /tmp/Miniconda3-py312_25.3.1-1-Linux-x86_64.sh \
    && bash /tmp/Miniconda3-py312_25.3.1-1-Linux-x86_64.sh -b -f -p /opt/miniconda3 \
    && rm /tmp/Miniconda3-py312_25.3.1-1-Linux-x86_64.sh \
    && /opt/miniconda3/bin/conda init bash

ENV PATH="/opt/miniconda3/bin:${PATH}"

# Install Rust which is required by TRL's dependency 'outlines'
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

ENV PATH="/root/.cargo/bin:${PATH}"

# Install Python dependencies before installing TRL with VLLM backend
RUN pip install -v torch==2.6.0 transformers datasets accelerate peft deepspeed wandb math_verify

# # Install FlashInfer
RUN pip install flashinfer-python -i https://flashinfer.ai/whl/cu126/torch2.6/

# Install TRL with VLLM backend
RUN PKG_CONFIG_PATH=/opt/miniconda3/lib/pkgconfig pip install trl[vllm]
