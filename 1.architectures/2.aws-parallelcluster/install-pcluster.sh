#!/bin/bash

# Create Virtual env
python3 -m pip install --upgrade pip
python3 -m pip install --user --upgrade virtualenv

python3 -m virtualenv ~/apc-ve

source ~/apc-ve/bin/activate

pip3 install awscli

pip3 install aws-parallelcluster
