#!/usr/bin/env  python3
import pytest
import os

def test_img_data_processing(docker_build):
    print(f"module file {os.path.dirname(__file__)}")
    print(f"cwd {os.getcwd()}")
    docker_build('megatron-preprocess', '0.data-preprocessing.Dockerfile')

def test_img_megatron_training(docker_build, docker_run):
    img = docker_build('megatron-preprocess', '2.distributed-training.Dockerfile')
    docker_run(img, ['python3', '-c', 'import torch'])
