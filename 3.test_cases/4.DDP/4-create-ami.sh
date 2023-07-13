#!/bin/bash

cd ./.env/ami/
packer build -color=true -var-file variables.json nvidia-efa-ml-al2-enroot_pyxis.json | tee build_AL2.log
cd ../..
