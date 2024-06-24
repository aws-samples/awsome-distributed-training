#!/usr/bin/env bash

region=us-west-2
dlc_account_id=658645717510
aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $dlc_account_id.dkr.ecr.$region.amazonaws.com

docker build -t smpv2 .
enroot import -o smpv2.sqsh  dockerd://smpv2:latest
