#! /bin/bash

if [ -z "$SLURM_JOB_ID" ]; then
    echo "Run with slurm: srun ./build_docker.sh"
    exit 1
fi

docker build --progress=plain -f colossalai.Dockerfile -t colossalai:latest .

if [ $? -ne 0 ]; then
    echo "Failed to build docker image"
    exit 1
fi

if [ -z "$DOCKER_REPO" ]; then
    echo "DOCKER_REPO is not set"
    exit 1
fi

docker tag colossalai:latest $DOCKER_REPO:latest

docker push $DOCKER_REPO:latest
