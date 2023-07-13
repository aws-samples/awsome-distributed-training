#!/bin/bash

aws ec2 create-key-pair --key-name pcluster-key --query KeyMaterial --output text > pcluster-key.pem
sudo chmod 600 pcluster-key.pem
