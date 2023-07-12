FROM mosaicml/pytorch:2.0.1_cu118-python3.10-ubuntu20.04

COPY llm-foundry llm-foundry
RUN cd llm-foundry \
    && pip install -e ".[gpu]" \
    && pip install xformers nvtx
COPY NsightSystems-linux-cli-public-2023.2.1.122-3259852.deb NsightSystems-linux-cli-public-2023.2.1.122-3259852.deb
RUN apt-get install -y libglib2.0-0 \
    && dpkg -i NsightSystems-linux-cli-public-2023.2.1.122-3259852.deb
