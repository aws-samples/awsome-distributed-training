SHELL := /bin/bash

default: help

help: # Show help for each of the Makefile recipes.
	@grep -E '^[a-zA-Z0-9 -]+:.*#'  Makefile | sort | while read -r l; do printf "\033[1;32m$$(echo $$l | cut -f 1 -d':')\033[00m:$$(echo $$l | cut -f 2- -d'#')\n"; done


build-image: # Build docker image
	bash scripts/build-image.sh

run-container: # Run docker container locally for debugging
	bash scripts/run-container.sh

run-benchmark: # Run single node benchmark locally
	bash scripts/run-benchmarks.sh
