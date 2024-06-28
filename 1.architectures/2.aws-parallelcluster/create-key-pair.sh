#!/bin/bash

aws ec2 create-key-pair --key-name pcluster-workshop-key --query KeyMaterial --output text > pcluster-workshop-key.pem
sudo chmod 600 pcluster-workshop-key.pem
