all: build clean import

build:
	docker build -t megatron-training -f 0.distributed-training.Dockerfile .

clean:
	-rm megatron-training.sqsh

import:
	enroot import -o megatron-training.sqsh  dockerd://megatron-training:latest