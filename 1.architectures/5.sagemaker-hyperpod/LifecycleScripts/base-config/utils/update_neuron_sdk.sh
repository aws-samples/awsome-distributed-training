#!/bin/bash
set -euxo pipefail
if neuron-top -v &> /dev/null
then 
    echo "Update to Neuron SDK Release 2.19.0"
    # Configure Linux for Neuron repository updates
    . /etc/os-release

    sudo echo "deb https://apt.repos.neuron.amazonaws.com ${VERSION_CODENAME} main" | sudo tee /etc/apt/sources.list.d/neuron.list 
    wget -qO - https://apt.repos.neuron.amazonaws.com/GPG-PUB-KEY-AMAZON-AWS-NEURON.PUB | sudo apt-key add -

    # Update OS packages
    sudo apt-get update -y

    # Install git
    sudo apt-get install git -y

    # Remove preinstalled packages and Install Neuron Driver and Runtime
    sudo apt-get remove aws-neuron-dkms -y
    sudo apt-get remove aws-neuronx-dkms -y
    sudo apt-get remove aws-neuronx-oci-hook -y
    sudo apt-get remove aws-neuronx-runtime-lib -y
    sudo apt-get remove aws-neuronx-collectives -y
    sudo apt-get install aws-neuronx-dkms=2.17.17.0 -y
    sudo apt-get install aws-neuronx-oci-hook=2.4.4.0 -y
    sudo apt-get install aws-neuronx-runtime-lib=2.21.41.0* -y
    sudo apt-get install aws-neuronx-collectives=2.21.46.0* -y

    # Remove pre-installed package and Install Neuron Tools
    sudo apt-get remove aws-neuron-tools  -y
    sudo apt-get remove aws-neuronx-tools  -y
    sudo apt-get install aws-neuronx-tools=2.18.3.0 -y
fi