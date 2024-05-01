import math
import os
import argparse

import torch
import torch.optim as optim
from transformers import AutoModelForCausalLM, AutoTokenizer
from transformers import AutoModel
from torch import distributed as dist
from torch.distributed.fsdp import FullyShardedDataParallel as FSDP
from torch.optim.lr_scheduler import LambdaLR

from config import (
    train_config,
    checkpointing,
    wrapper
)
from utils.checkpointing_utils import Checkpointer
from utils.config_utls import get_model_config, update_config
from utils.train_utils import (
    get_policies,
    get_profiler,
    setup,
    setup_environ_flags,
    train,
    create_pretraining_dataset
)

def parse_arge():
    """Parse the arguments."""
    parser = argparse.ArgumentParser()
    # add model id and dataset path argument
    parser.add_argument(
        "--model_name",
        type=str,
        default="llama2_7b",
        help="Model to use for training.",
    )
    parser.add_argument("--dataset_path", type=str, default="/fsx/data/examples_datasets/wikicorpus_llama2_7B_tokenized_4k", help="Path to dataset.")

    parser.add_argument("--ckpt_load_path", type=str, default="/fsx/llama2/pretrain/ckpt", help="path to load checkpoints from.")
    parser.add_argument("--ckpt_save_path", type=str, default="/fsx/llama2/pretrain/ckpt", help="path to load checkpoints from.")
    parser.add_argument("--fsdp_activation_checkpointing", type=bool)
    parser.add_argument("--selective_checkpointing", type=int, default=1)

    parser.add_argument("--sharding_strategy", type=str, default="fsdp", help="FSDP sharding strategy.")

    parser.add_argument("--low_cpu_fsdp", type=bool)
    parser.add_argument("--batch_size", type=int, default=2, help="Batch size for the training run.")

    parser.add_argument("--report_interval", type=int, default=200, help="Reporting interval for the training run.")

    parser.add_argument("--checkpoint_interval", type=int, default=20000, help="Checkpoint interval for the training run.")

    parser.add_argument("--use_torch_compile", type=bool)

    parser.add_argument("--use_profiler", type=bool)

    parser.add_argument("--use_wandb", type=bool)

    parser.add_argument("--num_steps", type=int, default=2000, help="Number of steps to train for.")

    parser.add_argument("--learning_rate", type=float, default=3e-4)

    parser.add_argument("--grad_clip_thresh", type=float, default=4.0)

    args = parser.parse_known_args()
    return args

def main():

    args, _ = parse_arge()
    cfg = train_config.training_config()

    update_config(cfg, args)

    torch.cuda.manual_seed(cfg.seed)
    torch.manual_seed(cfg.seed)

    setup()

    rank = dist.get_rank()
    device = rank % torch.cuda.device_count()
    world_size = dist.get_world_size()
    local_rank = int(os.environ["LOCAL_RANK"])


    torch.cuda.set_device(device)
    torch.cuda.empty_cache()
    setup_environ_flags()

    if rank == 0:
        print(f"Starting up the environment with configs {cfg}")
    
    mixed_precision_policy, wrapping_policy, sharding_policy = get_policies(
        cfg, rank
    )

    model_config = get_model_config(cfg.model_name)

    if cfg.low_cpu_fsdp:
        if rank == 0:
            model = AutoModelForCausalLM.from_config(model_config)
        else:
            with torch.device("meta"):
                model = AutoModelForCausalLM.from_config(model_config)
    else:
        model = AutoModelForCausalLM.from_config(model_config)

    if rank == 0:
        total_params = sum(p.numel() for p in model.parameters() if p.requires_grad)
        print(f"\n --- model has {total_params / 1e6} Million parameters. \n")

    if rank == 0:
        print("Loading datasets...")
    train_dataloader = create_pretraining_dataset(cfg.dataset_path, cfg.batch_size, world_size, rank, cfg.seed)
    
    if rank == 0:
        print("Finished creating data loader")

    model.config.use_cache=False

    model = FSDP(
        model,
        auto_wrap_policy=wrapping_policy,
        mixed_precision=mixed_precision_policy,
        sharding_strategy=sharding_policy,
        use_orig_params=cfg.use_torch_compile,
        device_id = torch.cuda.current_device(),
        limit_all_gathers=True,
        sync_module_states=cfg.low_cpu_fsdp,
        param_init_fn=lambda module: (
            model.to_empty(device=torch.device("cuda"), recurse=False)
            if cfg.low_cpu_fsdp
            else None
        ),
    )

    if cfg.fsdp_activation_checkpointing:
        if rank == 0:
            print(f"---> applying FSDP checkpointing...")
        checkpointing.apply_fsdp_checkpointing(model, cfg.selective_checkpointing)

    if cfg.use_torch_compile:
        if rank ==0:
            print(f"---> ysubg tircg cinouke...")
        torch._dynamo.config.accumulated_cache_size_limit = 128
        model = torch.compile(model)


    optimizer = optim.AdamW(
        model.parameters(), lr=cfg.learning_rate, betas= (0.9, 0.95), weight_decay=0.1 
    )

    checkpointer = Checkpointer(
        cfg.save_ckpt_path, 1000, cfg.sharding_strategy, rank, local_rank
    )
    
    model, optimizer, train_dataloader, start_step, tokens_seen = checkpointer.load(
        model,
        optimizer,
        train_dataloader,
        path=os.path.join(cfg.load_ckpt_path, "checkpoints/"),
    ) 

    warmup_interval = min(2000, cfg.num_steps // 20)
    schedule = lambda x: min(
        1- (1- min(x, warmup_interval) / warmup_interval) ** 2,
        0.1
        + 0.5
        * (1 - 0.1)
        * (1 + math.cos(min(x, cfg.num_steps) / cfg.num_steps * math.pi))
    )

    schedular = LambdaLR(optimizer, lambda x: schedule(x + start_step))

    profiler = get_profiler(cfg)

    if rank == 0:
        print(f"Starting training for {cfg.num_steps} steps")

    train(
        cfg,
        model,
        local_rank,
        rank,
        train_dataloader,
        optimizer,
        schedular,
        profiler,
        checkpointer,
        start_step,
        tokens_seen
    )

    dist.barrier()
    dist.destroy_process_group()

if __name__ == "__main__":
    main()
    
    









