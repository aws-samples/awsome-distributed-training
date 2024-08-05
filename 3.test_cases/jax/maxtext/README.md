# MaxText test cases

MaxText is a high performance, highly scalable, open-source LLM written in pure Python/Jax and targeting Google Cloud TPUs and GPUs for training and inference. MaxText achieves high MFUs and scales from single host to very large clusters while staying simple and "optimization-free" thanks to the power of Jax and the XLA compiler.


## Building MaxText container

First, determine which MaxText for example we use `jetstream-v0.2.2` then identify JAX version compatible with the MaxText from https://github.com/google/maxtext/blob/jetstream-v0.2.2/constraints_gpu.txt. In this particlar case, it requires `jax==0.4.25`. 

The MaxText container image is based on the [JAX base image](..). Go to the directory and build the specific version of the image with the following command:

```bash
DOCKER_BUILDKIT=1 docker build --progress=plain \
    -f jax_paxml.Dockerfile -t jax:0.4.25 .
    --build-arg JAX_VERISON=0.4.25
```

then build the MaxText container image:

```bash
DOCKER_BUILDKIT=1 docker build --progress=plain -f maxtext.Dockerfile -t maxtext:jetstream-v0.2.2 .
    --build-arg JAX_VERISON=0.4.25
    --build-arg MAXTEXT_VERSION=jetstream-v0.2.2
```

