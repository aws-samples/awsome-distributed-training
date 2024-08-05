ARG JAX_VERSION
FROM jax:${JAX_VERSION}

ARG MAXTEXT_VERSION=jetstream-v0.2.2
ARG ENV_MODE=stable # "stable/nightly"
#############################
# Install TransformerEngine #
# Based on https://github.com/google/maxtext/blob/jetstream-v0.2.2/setup.sh

RUN pip3 install "transformer-engine==1.5.0+297459b" \
        --extra-index-url https://us-python.pkg.dev/gce-ai-infra/maxtext-build-support-packages/simple/ \
        -c constraints_gpu.txt


####################
# Install Maxtext  #
RUN git clone -b "${MAXTEXT_VERSION}" https://github.com/google/maxtext.git \
    && cd maxtext \
    && setup.sh MODE=${ENV_MODE} JAX_VERSION=${ENV_JAX_VERSION} DEVICE=${ENV_DEVICE}