import pytest
import os


def test_0_nccl_test(docker_build, docker_run):
    img = docker_build('nccl-test', '0.nccl-tests.Dockerfile')
    #docker_run(img, ['python3', '-c', 'import torch'])
