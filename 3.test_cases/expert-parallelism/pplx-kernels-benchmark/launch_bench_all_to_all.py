import argparse
from typing import Callable, Concatenate, ParamSpec
import torch
import os
from tests.bench_all_to_all import _worker_bench_all_to_all
from tests.distributed_utils import ProcessGroupInfo

P = ParamSpec("P")

def parallel_launch_from_torchrun(
    worker: Callable[Concatenate[ProcessGroupInfo, P], None],
    *args: P.args,
    **kwargs: P.kwargs,
) -> None:
    rank = int(os.environ.get("RANK", 0))
    world_size = int(os.environ.get("WORLD_SIZE", 1))
    world_local_size = torch.cuda.device_count()
    local_rank = rank % world_local_size
    node_rank = rank // world_local_size
    device = torch.device("cuda", local_rank)
    torch.cuda.set_device(device)
    torch.distributed.init_process_group(backend="cpu:gloo,cuda:nccl", device_id=device)
    try:
        worker(
            ProcessGroupInfo(
                world_size=world_size,
                world_local_size=world_local_size,
                rank=rank,
                node_rank=node_rank,
                local_rank=local_rank,
                device=device,
            ),
            *args,
            **kwargs,
        )
    finally:
        torch.distributed.destroy_process_group()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dp-size", type=int, default=1)
    parser.add_argument(
        "--in-dtype",
        choices=["bfloat16", "float16", "float8_e4m3fn"],
        default="float8_e4m3fn",
    )
    parser.add_argument(
        "--out-dtype",
        choices=["bfloat16", "float16"],
        default="bfloat16",
    )
    args = parser.parse_args()
    dp_size = int(args.dp_size)
    in_dtype = str(args.in_dtype)
    out_dtype = str(args.out_dtype)

    parallel_launch_from_torchrun(_worker_bench_all_to_all, dp_size, in_dtype, out_dtype)


if __name__ == "__main__":
    main()