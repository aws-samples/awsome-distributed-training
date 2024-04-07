ENROOT_IMAGE=deepspeed

all: build clean import

build:
	docker build -t ${ENROOT_IMAGE} -f 0.deepspeed.dockerfile .

clean:
	-rm ${ENROOT_IMAGE}.sqsh

import:
	enroot import -o ${ENROOT_IMAGE}.sqsh dockerd://${ENROOT_IMAGE}:latest
