FROM nvcr.io/nvidia/pytorch:23.08-py3

RUN git clone https://github.com/mosaicml/diffusion-benchmark.git /wd
RUN pip3 install -r /wd/requirements.txt
RUN pip3 install mosaicml==0.15.0 --force
RUN pip3 install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu121 --force
RUN pip3 uninstall transformer-engine -y
RUN pip3 install protobuf==3.20.3

WORKDIR /wd


