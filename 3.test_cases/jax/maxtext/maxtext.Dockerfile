ARG JAX_VERSION=0.4.25
FROM jax:${JAX_VERSION}

ARG MAXTEXT_VERSION=jetstream-v0.2.2
ARG ENV_MODE=stable # "stable/nightly"
ARG TE_VERSION=1.5.0+297459b

####################
# Install Maxtext  #
RUN git clone -b "${MAXTEXT_VERSION}" https://github.com/google/maxtext.git \
    && cd maxtext \
    && pip3 install "transformer-engine==${TE_VERSION}" \
        --extra-index-url https://us-python.pkg.dev/gce-ai-infra/maxtext-build-support-packages/simple/ \
        -c constraints_gpu.txt 
WORKDIR /maxtext
RUN pip3 install -r requirements.txt -c constraints_gpu.txt