FROM ubuntu:20.04

LABEL maintainer="Amazon AI"
LABEL dlc_major_version="1"

ARG PYTHON=python3.10
ARG PYTHON_VERSION=3.10.12

# Neuron SDK components version numbers
ARG NEURONX_RUNTIME_LIB_VERSION=2.*
ARG NEURONX_COLLECTIVES_LIB_VERSION=2.*
ARG NEURONX_TOOLS_VERSION=2.*
ARG NEURONX_FRAMEWORK_VERSION=2.*
ARG NEURONX_CC_VERSION=2.*

ARG OMPI_VERSION=4.1.5
ARG PIP=pip3

# This arg required to stop docker build waiting for region configuration while installing tz data from ubuntu 20
ARG DEBIAN_FRONTEND=noninteractive

# Python won’t try to write .pyc or .pyo files on the import of source modules
# Force stdin, stdout and stderr to be totally unbuffered. Good for logging
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONIOENCODING=UTF-8
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/opt/aws/neuron/lib"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/opt/amazon/efa/lib"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/opt/amazon/efa/lib64"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/opt/amazon/openmpi/lib64"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib"
ENV PATH /opt/aws/neuron/bin/:$PATH

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    emacs \
    git \
    jq \
    libopencv-dev \
    openjdk-8-jdk-headless \
    openjdk-8-jdk \
    openjdk-8-jre \
    libglib2.0-0 \
    libgl1-mesa-glx \
    libsm6 \
    libxext6 \
    libxrender-dev \
    openjdk-11-jdk \
    software-properties-common \
    wget \
    unzip \
    vim \
    zlib1g-dev \
    openssl \
    libssl-dev \
    libsqlite3-dev \
    libgdbm-dev \
    libc6-dev \
    libbz2-dev \
    tk-dev \
    libffi-dev \
    libcap-dev \
    gnupg2 \
    gpg-agent \
 && rm -rf /var/lib/apt/lists/* \
 && apt-get clean

RUN echo "deb https://apt.repos.neuron.amazonaws.com focal main" > /etc/apt/sources.list.d/neuron.list
RUN wget -qO - https://apt.repos.neuron.amazonaws.com/GPG-PUB-KEY-AMAZON-AWS-NEURON.PUB | apt-key add -

RUN apt-get update \
 && apt-get install -y \
    aws-neuronx-tools=$NEURONX_TOOLS_VERSION \
    aws-neuronx-collectives=$NEURONX_COLLECTIVES_LIB_VERSION \
    aws-neuronx-runtime-lib=$NEURONX_RUNTIME_LIB_VERSION \
 && rm -rf /var/lib/apt/lists/* \
 && rm -rf /tmp/tmp* \
 && apt-get clean

# Install Open MPI
RUN mkdir -p /tmp/openmpi \
 && cd /tmp/openmpi \
 && wget --quiet https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-${OMPI_VERSION}.tar.gz \
 && tar zxf openmpi-${OMPI_VERSION}.tar.gz \
 && cd openmpi-${OMPI_VERSION} \
 && ./configure --enable-orterun-prefix-by-default \
 && make -j $(nproc) all \
 && make install \
 && ldconfig \
 && rm -rf /tmp/openmpi

# install Python
RUN wget -q https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz \
 && tar -xzf Python-$PYTHON_VERSION.tgz \
 && cd Python-$PYTHON_VERSION \
 && ./configure --enable-shared --prefix=/usr/local \
 && make -j $(nproc) && make install \
 && cd .. && rm -rf ../Python-$PYTHON_VERSION* \
 && ln -s /usr/local/bin/pip3 /usr/bin/pip \
 && ln -s /usr/local/bin/$PYTHON /usr/local/bin/python \
 && ${PIP} --no-cache-dir install --upgrade \
    pip \
    setuptools

WORKDIR /

# The ENV variables declared below are changed in the previous section
# Grouping these ENV variables in the first section causes
# ompi_info to fail. This is only observed in CPU containers
ENV PATH="$PATH:/home/.openmpi/bin"
ENV LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/home/.openmpi/lib/"
RUN ompi_info --parsable --all | grep mpi_built_with_cuda_support:value

# EFA Installer does apt get. Make sure to run apt update before that
RUN apt-get update
RUN cd $HOME \
    && curl -O https://efa-installer.amazonaws.com/aws-efa-installer-latest.tar.gz \
    && wget https://efa-installer.amazonaws.com/aws-efa-installer.key && gpg --import aws-efa-installer.key \
    && cat aws-efa-installer.key | gpg --fingerprint \
    && wget https://efa-installer.amazonaws.com/aws-efa-installer-latest.tar.gz.sig && gpg --verify ./aws-efa-installer-latest.tar.gz.sig \
    && tar -xf aws-efa-installer-latest.tar.gz \
    && cd aws-efa-installer \
    && ./efa_installer.sh -y -g -d --skip-kmod --skip-limit-conf --no-verify \
    && cd $HOME

RUN mkdir -p /etc/pki/tls/certs && cp /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt
RUN ${PIP} config set global.extra-index-url https://pip.repos.neuron.amazonaws.com \
    && ${PIP} install --force-reinstall torch-neuronx==$NEURONX_FRAMEWORK_VERSION --extra-index-url https://pip.repos.neuron.amazonaws.com \
    && ${PIP} install --force-reinstall neuronx-cc==$NEURONX_CC_VERSION --extra-index-url https://pip.repos.neuron.amazonaws.com \
    && ${PIP} install --force-reinstall neuronx_distributed --extra-index-url https://pip.repos.neuron.amazonaws.com

# awscli 1.25.47 has requirement docutils<0.17,>=0.10
# etcd for kubernetes installation
# awscli 1.27.127 has requirement rsa<4.8,>=3.1.2, but you have rsa 4.9.
# awscli 1.27.127 requires urllib3 < 1.27, python-etcd requires urllib3 >= 1.7, latest urllib3 release is 2.0.2
RUN ${PIP} install --no-cache-dir -U \
    "attrs<24,>=23.1.0" \
    "protobuf>=3.18.3,<=3.20.3" \
    "docutils>=0.10,<0.17" \
    "rsa<4.8,>=3.1.2" \
    "python-etcd" \
    "urllib3>=1.26.0,<1.27"
