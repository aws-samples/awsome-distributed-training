#!/usr/bin/env python

"""
All-reduce on one GPU, to probe libraries opened. This script can be run without torchrun.

Usage:

    ./conda_env_pytorch/bin/python all_reduce_bench.py
"""
import os
import torch

def main():
    os.environ.setdefault('MASTER_ADDR', 'localhost')
    os.environ.setdefault('MASTER_PORT', '0')
    os.environ.setdefault('RANK', '0')
    torch.cuda.set_device(0)
    torch.distributed.init_process_group('nccl', world_size=1)
    X = torch.rand(500, 2, dtype=torch.float32).cuda(0)
    torch.distributed.all_reduce(X)
    torch.cuda.synchronize()
    if torch.distributed.get_rank() == 0:
        print(f"Test completed.")

if __name__ == "__main__":
    main()
