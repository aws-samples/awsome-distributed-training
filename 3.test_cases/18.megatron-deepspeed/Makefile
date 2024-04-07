ENROOT_IMAGE=gpt-neox

all: build clean import

build:
	docker build -t ${ENROOT_IMAGE} -f 0.gpt-neox.dockerfile .

clean:
	-rm ${ENROOT_IMAGE}.sqsh

import:
	enroot import -o ${ENROOT_IMAGE}.sqsh dockerd://${ENROOT_IMAGE}:latest
