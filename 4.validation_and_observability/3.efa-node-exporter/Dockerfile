FROM public.ecr.aws/docker/library/ubuntu:20.04

ARG EFA_INSTALLER_VERSION=1.30.0
ARG NODE_EXPORTER_VERSION=v1.6.1
ARG PROCFS_EXPORTER_VERSION=v0.12.0
ARG GOLANG_VERSION=1.21.5

# install go
RUN apt update && apt install curl git build-essential -y
RUN curl -OL https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz && \
    tar -C /usr/local -xf go${GOLANG_VERSION}.linux-amd64.tar.gz
ENV PATH=$PATH:/usr/local/go/bin

# Install EFA
RUN cd $HOME \
    && curl -O https://efa-installer.amazonaws.com/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && tar -xf $HOME/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && cd aws-efa-installer \
    && ./efa_installer.sh -y -g -d --skip-kmod --skip-limit-conf --no-verify \
    && rm -rf $HOME/aws-efa-installer

# Install ProcFS
RUN git clone -b $PROCFS_EXPORTER_VERSION https://github.com/prometheus/procfs.git /workspace/procfs
COPY class_amazon_efa.go  /workspace/procfs/sysfs/
RUN cd /workspace/procfs && make test

# Install Node Exporter
RUN git clone -b $NODE_EXPORTER_VERSION https://github.com/prometheus/node_exporter.git /workspace/node_exporter
COPY amazon_efa_linux.go /workspace/node_exporter/collector/

WORKDIR /workspace/node_exporter
RUN  go mod edit --replace=github.com/prometheus/procfs=/workspace/procfs
RUN  go mod tidy && go build -o node_exporter
ENTRYPOINT ["./node_exporter"]
