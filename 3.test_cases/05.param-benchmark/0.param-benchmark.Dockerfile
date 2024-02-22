FROM 763104351884.dkr.ecr.us-east-1.amazonaws.com/pytorch-training:2.0.1-gpu-py310-cu118-ubuntu20.04-ec2

RUN git clone https://github.com/facebookresearch/param.git && \
    cd param && git checkout 6236487e8969838822b52298c2a2318f6ac47bbd

WORKDIR /param/train/comms/pt
