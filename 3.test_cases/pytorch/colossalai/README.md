# Colossal-AI

## Dependencies

As of Apr 18th 2025 [commit](https://github.com/hpcaitech/ColossalAI/tree/46ed5d856b16b074325091a88e761544b3d4f9f0) ColosalAI required PyTorch 2.5.1 which official builds use CUDA 12.4. We use `nvidia/cuda:12.4.1-devel-ubuntu22.04` as the base image and install all dependencies on top of it in [colossalai.Dockerfile](colossalai.Dockerfile).

## Build Docker Image

Building Colossal-AI from scratch requires GPU support, you need to use Nvidia Docker Runtime as the default when doing docker build. We launch the build job on the GPU node:

Login to AWS ECR:
```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...

aws ecr get-login-password ...
```

Build the docker image on the GPU node and push it to the docker repo:
```bash
export DOCKER_REPO=159553542841.dkr.ecr.ap-northeast-1.amazonaws.com/belevich/colossalai
srun ./build_docker.sh
```

Take docker image from the docker repo:
```bash
docker pull $DOCKER_REPO:latest
```

Import the docker image to an enroot container(maybe remove previous created `rm ./colossalai.sqsh`):
```bash
enroot import -o ./colossalai.sqsh  dockerd://$DOCKER_REPO:latest
```


