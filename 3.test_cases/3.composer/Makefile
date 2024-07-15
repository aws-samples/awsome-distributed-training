ENROOT_IMAGE=composer

all: build clean import

build:
	docker build -t ${ENROOT_IMAGE} -f 0.composer.Dockerfile .

clean:
	-rm ${ENROOT_IMAGE}.sqsh

import:
	enroot import -o ${ENROOT_IMAGE}.sqsh dockerd://composer:latest
