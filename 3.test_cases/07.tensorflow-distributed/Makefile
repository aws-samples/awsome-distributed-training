ENROOT_IMAGE=tensorflow

all: build clean import

build:
	docker build -t ${ENROOT_IMAGE} -f 0.tensorflow.Dockerfile .

clean:
	-rm ${ENROOT_IMAGE}.sqsh

import:
	enroot import -o ${ENROOT_IMAGE}.sqsh dockerd://tensorflow:latest
