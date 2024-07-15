FROM nvidia-pt-aws:latest
COPY requirements.txt requirements.txt
RUN pip install -r requirements.txt
# Temporally removing TE due to https://github.com/chenfei-wu/TaskMatrix/issues/116
RUN pip uninstall -y transformer-engine flash-attn