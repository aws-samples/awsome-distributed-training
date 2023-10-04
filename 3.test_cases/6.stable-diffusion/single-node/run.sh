#!/bin/bash

docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -it mosaicml-stable-diffusion /bin/bash
