FROM pplx-garden:latest

RUN apt-get update && apt-get install -y \
    sudo \
    libnuma-dev

COPY uccl /opt/uccl
RUN cd /opt/uccl \
    && cd ep \
    && ./install_deps.sh \
    && make -j install

ENV PYTHONPATH=/opt/uccl/ep/bench:$PYTHONPATH
