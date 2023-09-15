# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Container file for data prep
# This could be reduced in the future
FROM nvcr.io/nvidia/pytorch:23.05-py3
RUN apt-get update -y && apt-get install wget xz-utils git -y
RUN apt-get install python3 python3-pip -y
RUN pip3 install nltk
RUN git clone https://github.com/NVIDIA/Megatron-LM.git
