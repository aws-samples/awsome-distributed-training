# JAX container for Amazon EC2 GPU accelerated Instances

Ths directory contains a sample Dockerfile `jax_paxml.Dockerfile` to run [JAX](https://github.com/google/jax) and [Paxml](https://github.com/google/paxml) on AWS.

## Container description

In principle, the reference `Dockerfile` does the following:

- Provide JAX built for NVIDIA CUDA devices, by using a recent NVIDIA CUDA image as the
  parent image.
- Remove unneccessary networking packages that might conflict with AWS technologies.
- Install EFA user-space libraries. It's important to avoid building the kernel drivers during
  `docker build`, and skip the self-tests, as both of these steps fail are expected to fail when run
  during container build.
- Install NCCL recommended version.
- Install [aws-ofi-nccl](https://github.com/aws/aws-ofi-nccl) to get NCCL to utilize EFA.
- Install JAX.
- Install Paxml.
- Install Praxis.

## Build the container

Build the jax container as follow

```bash
# Build a container image
DOCKER_BUILDKIT=1 docker build --progress=plain -f jax_paxml.Dockerfile -t paxml:jax-0.4.18-1.2.0 .

# Verify the image has been built
docker images
```

Convert container to enroot format

```bash
# Convert to enroot format. Attempt to remove an existing .sqsh, otherwise enroot refuses to
# run when the output .sqsh file already exists.
rm /fsx/paxml_jax-0.4.18-1.2.0.sqsh ; enroot import -o /fsx/paxml_jax-0.4.18-1.2.0.sqsh dockerd://paxml:jax-0.4.18-1.2.0
```

Tips: when building on a compute node (or a build node), you save the built Docker image on a shared
filesystem such as `/fsx`, to allow other nodes (e.g., head node, or other compute nodes) to load
the image to their local Docker registry.

```bash
# Build node: save image to file
docker save paxml:jax-0.4.18-1.2.0 > /fsx/paxml_jax-0.4.18-1.2.0.sqsh.tar

# Load image to local docker registry -> on head node, or new compute/build node
docker load < /fsx/paxml_jax-0.4.18-1.2.0.tar

# Verify the image has been loaded
docker images
```
