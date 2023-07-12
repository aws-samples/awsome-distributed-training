#!/bin/bash

# Install pip and other dependencies
sudo apt install python3-pip
sudo apt-get install unzip

# Make sure you have installed the AWS Command Line Interface:
pip3 install awscli

# Packer - Ubuntu
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install packer

# Packer - Amazon Linux
#sudo yum install -y yum-utils
#sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
#sudo yum -y install packer

# Pcluster Dependencies
python3 -m pip install flask==2.2.5
# Node.js
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash
chmod ug+x ~/.nvm/nvm.sh
source ~/.nvm/nvm.sh
nvm install --lts
node --version


# Install AWS ParallelCluster:
pip3 install aws-parallelcluster==3.1.4
