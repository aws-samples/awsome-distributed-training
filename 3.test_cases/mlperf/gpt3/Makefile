IMAGE=nemo-megatron

all: build clean import

build:
	docker build -t ${IMAGE} -f nemo-megatron.Dockerfile .

clean:
	-rm ${IMAGE}.sqsh

import:
	enroot import -o ${IMAGE}.sqsh dockerd://${IMAGE}:latest