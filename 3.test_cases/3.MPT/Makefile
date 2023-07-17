SHELL := /bin/bash

default: help

help: # Show help for each of the Makefile recipes.
	@grep -E '^[a-zA-Z0-9 -]+:.*#'  Makefile | sort | while read -r l; do printf "\033[1;32m$$(echo $$l | cut -f 1 -d':')\033[00m:$$(echo $$l | cut -f 2- -d'#')\n"; done

##################################################
# Container Creation and Single node benchmarks
##################################################

build-image: # Build docker image
	bash scripts/build-image.sh

run-container: # Run docker container locally for debugging
	bash scripts/run-container.sh

run-benchmark: build-image # Run single node benchmark locally
	bash scripts/run-benchmarks.sh


##################################################
# Multi-node benchmarks with ParallelCluster
##################################################

install-node: # Insatall node command
	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash
	chmod ug+x ~/.nvm/nvm.sh
	source ~/.nvm/nvm.sh
	nvm install --lts
	node --version

install-pcluster: # Install pcluster cli command using pip
	python3 -m pip install --upgrade pip
	python3 -m pip install --user --upgrade virtualenv
	python3 -m virtualenv ~/deepspeed-on-aws-tutorials-venv
	source ~/deepspeed-on-aws-tutorials-venv/bin/activate
	python3 -m pip install --upgrade "aws-parallelcluster==3.6.0"

deploy-s3: # Deploy S3 bucket using CloudFormation
	bash scripts/deploy-s3.sh

deploy-vpc: # Deploy VPC using CloudFormation
	bash scripts/deploy-vpc.sh

deploy-pcluster:
	bash scripts/deploy-pcluster.sh