import os

try:
    import packaging.version
except ImportError:
    from pkg_resources import packaging  # type: ignore

import time
from datetime import timedelta

import torch
import torch.cuda.nccl as nccl
import torch.distributed as dist
from torch.distributed.fsdp import ShardingStrategy

from config import (
    train_config,
    checkpointing,
    wrapper,
    mixed_precision
)

from transformers import default_data_collator
from torch.utils.data.dataloader import DataLoader
import datasets
from torch.utils.data import DistributedSampler
from transformers import set_seed


def train(
    cfg,
    model,
    local_rank,
    rank,
    train_loader,
    optimizer,
    scheduler,
    profiler,
    checkpointer,
    start_step,
    tokens_seen,
):
    if cfg.use_wandb:
        try:
            import wandb
        except ImportError:
            raise ImportError(
                "use_wandb is set to True but wandb is not installed. Please install wandb to use wandb support."
            )

        if rank == 0:
            print(
                f"--> wandb is enabled! Make sure to pass your wandb api key via WANDB_API_KEY"
            )
            wandb.init(
                project=cfg.wandb_project_name,
                dir=cfg.wandb_dir,
                resume="allow",
                id=cfg.wandb_run_id,
            )
            wandb.config = {
                "learning_rate": cfg.learning_rate,
                "steps": cfg.num_steps,
                "batch_size": cfg.batch_size,
            }

    model.train()
    ddp_stats = torch.zeros(3).to(local_rank)

    start = time.time()
    loop_start = time.time()
    for batch_idx, batch in enumerate(train_loader, start=start_step + 1):
        if batch_idx > cfg.num_steps:
            break
        input, label = batch['input_ids'], batch['labels']
        input = input.to(local_rank)
        label = label.to(local_rank)

        optimizer.zero_grad()
        output = model(input_ids=input, labels=label)
        #ce_loss = torch.nn.CrossEntropyLoss()
        #loss = ce_loss(output.view(-1, output.size(-1)), label.view(-1).long())
        loss = output["loss"]

        loss.backward()
        ddp_stats[1] += model.clip_grad_norm_(cfg.grad_clip_thresh).item()
        optimizer.step()
        scheduler.step()

        ddp_stats[0] += loss.item()
        ddp_stats[2] += 1

        if profiler:
            profiler.step()

        if batch_idx % cfg.report_interval == 0:
            dist.all_reduce(ddp_stats, op=dist.ReduceOp.SUM)
            train_loss = ddp_stats[0] / ddp_stats[2]
            g_norm = ddp_stats[1] / ddp_stats[2]
            elapsed_time = time.time() - loop_start
            world_size = int(os.environ["WORLD_SIZE"])
            new_tokens_seen = (
                (batch_idx - start_step) * world_size * cfg.batch_size * cfg.seq_length
            )
            if rank == 0:
                total_tokens_seen = tokens_seen + new_tokens_seen
                current_loss = train_loss.item()
                current_lr = scheduler.get_last_lr()[0]
                current_gnorm = g_norm.item()
                overall_throughput = int(new_tokens_seen / world_size / elapsed_time)
                reserved_mem = torch.cuda.max_memory_reserved(
                    device=torch.cuda.current_device()
                )
                allocated_mem = torch.cuda.max_memory_allocated(
                    device=torch.cuda.current_device()
                )

                print("step:", batch_idx)
                print("tokens seen:", total_tokens_seen)
                print("loss:", current_loss)
                print("gradient norm:", current_gnorm)
                print(
                    f"speed for these {cfg.report_interval} steps:",
                    (time.time() - start) / cfg.report_interval,
                )
                print("overall speed:", elapsed_time / (batch_idx - start_step))
                print("LR:", current_lr)
                print("reserved memory:", reserved_mem)
                print("allocated memory:", allocated_mem)
                print("overall token per gpu per sec:", overall_throughput)
                print("token per day:", int(new_tokens_seen / elapsed_time * 3600 * 24))
                if cfg.use_wandb:
                    wandb.log(
                        {
                            "learning rate": current_lr,
                            "loss": current_loss,
                            "gradient norm": current_gnorm,
                            "token seen": total_tokens_seen,
                            "throughput (token per gpu per sec)": overall_throughput,
                            "gpu reserved memory": reserved_mem,
                            "gpu allocated memory": allocated_mem,
                        },
                        step=batch_idx,
                    )
            start = time.time()
            ddp_stats.zero_()
        torch.cuda.reset_peak_memory_stats(device=torch.cuda.current_device())

        if batch_idx % cfg.checkpoint_interval == 0:
            checkpointer.save(
                batch_idx,
                model,
                optimizer,
                train_loader,
                tokens_seen=tokens_seen + new_tokens_seen,
            )

    return train_loss


def setup():
    dist.init_process_group()


def setup_environ_flags():
    os.environ["TORCH_SHOW_CPP_STACKTRACES"] = str(1)
    os.environ["TORCH_NCCL_ASYNC_ERROR_HANDLING"] = str(1)


def get_policies(cfg, rank):
    """Get the policies for mixed precision and fsdp wrapping and sharding strategy"""

    verify_bfloat_support = (
        torch.version.cuda
        and torch.cuda.is_bf16_supported()
        and packaging.version.parse(torch.version.cuda).release >= (11, 0)
        and dist.is_nccl_available()
        and nccl.version() >= (2, 10)
    )

    # mixed precision
    if cfg.mixed_precision:
        bf16_ready = verify_bfloat_support
        if bf16_ready:
            mixed_precision_policy = mixed_precision.bfSixteen
            if rank == 0:
                print(f"bFloat16 enabled for mixed precision - using bfSixteen policy")
        else:
            mixed_precision_policy = mixed_precision.fpSixteen
            if rank == 0:
                print(f"FP16 enabled")
    else:
        mixed_precision_policy = None

    # wrapping policy
    wrapping_policy = wrapper.get_wrapper(cfg.model_name)

    # sharding strategy
    if cfg.sharding_strategy == "fsdp":
        sharding_strategy = ShardingStrategy.FULL_SHARD
    elif cfg.sharding_strategy == "hsdp":
        sharding_strategy = ShardingStrategy.HYBRID_SHARD
    elif cfg.sharding_strategy == "ddp":
        sharding_strategy = ShardingStrategy.NO_SHARD
    else:
        sharding_strategy = ShardingStrategy.FULL_SHARD
    if rank == 0:
        print(f"Sharding strategy = {cfg.sharding_strategy}")

    return mixed_precision_policy, wrapping_policy, sharding_strategy


def get_profiler(cfg):
    if cfg.use_profiler:
        profiler = torch.profiler.profile(
            activities=[
                torch.profiler.ProfilerActivity.CPU,
                torch.profiler.ProfilerActivity.CUDA,
            ],
            schedule=torch.profiler.schedule(wait=1, warmup=2, active=3, repeat=1),
            on_trace_ready=torch.profiler.tensorboard_trace_handler("profile_traces"),
            profile_memory=True,
            with_stack=False,
            record_shapes=True,
            with_flops=True
        )
    else:
        profiler = None
    return profiler

def create_pretraining_dataset(
    data_dir, mini_batch_size, dp_size, dp_rank, seed
):
    #Workaround because python functions are not picklable
    class WorkerInitObj(object):
        def __init__(self, seed):
            self.seed = seed

        def __call__(self, id):
            set_seed(self.seed)
    worker_init = WorkerInitObj(seed)
    train_data = datasets.load_from_disk(data_dir)
    train_sampler = DistributedSampler(
        train_data,
        num_replicas=dp_size,
        rank=dp_rank,
        shuffle=False,
        drop_last=True,
    )
    train_dataloader = DataLoader(
        train_data,
        collate_fn=default_data_collator,
        sampler=train_sampler,
        batch_size=mini_batch_size,
        num_workers=0,
        worker_init_fn=worker_init,
        drop_last=True,
        pin_memory=True,
    )
    return train_dataloader