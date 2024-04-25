# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import os
import argparse
import math
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    set_seed,
    get_scheduler,
    SchedulerType,
    FalconConfig
)

from transformers.models.falcon.modeling_falcon import FalconDecoderLayer
from datasets import load_from_disk
import torch
import torch.distributed as dist
from utils import create_dataloaders,save_model
import time
from tqdm import tqdm

import functools
from torch.distributed.fsdp import (
    FullyShardedDataParallel as FSDP,
    MixedPrecision,
    ShardingStrategy,
    BackwardPrefetch,
    CPUOffload,
    
)

import torch_xla.core.xla_model as xm
import torch_xla.distributed.parallel_loader as pl

from torch.distributed.algorithms._checkpoint.checkpoint_wrapper import (
    checkpoint_wrapper,
    CheckpointImpl,
    apply_activation_checkpointing)

from torch.distributed.fsdp.wrap import (
    transformer_auto_wrap_policy,
)


def parse_arge():
    """Parse the arguments."""
    parser = argparse.ArgumentParser()
    # add model id and dataset path argument
    parser.add_argument(
        "--model_id",
        type=str,
        default="google/flan-t5-xl",
        help="Model id to use for training.",
    )
    parser.add_argument("--dataset_path", type=str, default="lm_dataset", help="Path to dataset.")
    # add training hyperparameters for epochs, batch size, learning rate, and seed
    parser.add_argument("--epochs", type=int, default=1, help="Number of epochs to train for.")
    parser.add_argument("--max_steps", type=int, default=None, help="Number of epochs to train for.")
    parser.add_argument(
        "--per_device_train_batch_size",
        type=int,
        default=1,
        help="Batch size to use for training.",
    )
    parser.add_argument("--lr", type=float, default=3e-5, help="Learning rate to use for training.")
    parser.add_argument("--optimizer", type=str, default="adamw_hf", help="Learning rate to use for training.")
    parser.add_argument("--seed", type=int, default=42, help="Seed to use for training.")
    parser.add_argument("--num_train_epochs", type=int, default=1, help="Total number of training epochs to perform.")

    parser.add_argument(
        "--gradient_checkpointing",
        type=bool,
        default=True,
        help="Path to deepspeed config file.",
    )
    parser.add_argument(
        "--bf16",
        type=bool,
        default=False,
        help="Whether to use bf16.",
    )
    parser.add_argument("--fsdp", type=str, default=None, help="Whether to use fsdp.")
    parser.add_argument(
        "--fsdp_transformer_layer_cls_to_wrap",
        type=str,
        default=None,
        help="Which transformer layer to wrap with fsdp.",
    )
    parser.add_argument(
        "--max_train_steps",
        type=int,
        default=None,
        help="Total number of training steps to perform. If provided, overrides num_train_epochs.",
    )
    parser.add_argument(
        "--learning_rate",
        type=float,
        default=5e-5,
        help="Initial learning rate (after the potential warmup period) to use.",
    )
    parser.add_argument(
        "--gradient_accumulation_steps",
        type=int,
        default=1,
        help="Number of updates steps to accumulate before performing a backward/update pass.",
    )
    parser.add_argument(
        "--lr_scheduler_type",
        type=SchedulerType,
        default="linear",
        help="The scheduler type to use.",
        choices=["linear", "cosine", "cosine_with_restarts", "polynomial", "constant", "constant_with_warmup"],
    )
    parser.add_argument(
        "--num_warmup_steps", type=int, default=0, help="Number of steps for the warmup in the lr scheduler."
    )
    parser.add_argument("--limit_all_gathers", type=bool, default=False)
    parser.add_argument("--forward_prefetch", type=bool, default=False)
    parser.add_argument("--weight_decay", type=float, default=0.0, help="Weight decay to use.")
    parser.add_argument("--cache_dir",type=str,default=None)

    args = parser.parse_known_args()
    return args


def training_function(args):
    # set seed
    set_seed(args.seed)
    
    dataset = load_from_disk(args.dataset_path)
    # load model from the hub
    config = FalconConfig(vocab_size=65024,
                          use_cache=True,
                          parallel_attn=True,
                          num_hidden_layers=16,
                          num_attention_heads=71,
                          new_decoder_architecture=False,
                          multi_query=True,
                          layer_norm_epsilon=1e-05,
                          initializer_range=0.02,
                          hidden_size=2272,
                          hidden_dropout=0.0,
                          eos_token_id=11,
                          bos_token_id=11,
                          bias=False)


    model = AutoModelForCausalLM.from_config(config)
    

    tokenizer = AutoTokenizer.from_pretrained(args.model_id)

    train_dataset = dataset["train"]
    eval_dataset = dataset["validation"]

    train_dataloader,eval_dataloader = create_dataloaders(train_dataset,eval_dataset,args.rank,args.world_size,args.seed,args.per_device_train_batch_size,args.per_device_train_batch_size)
    #train_dataloader = pl.MpDeviceLoader(train_dataloader, device)
    #eval_dataloader = pl.MpDeviceLoader(eval_dataloader, device)

    device = xm.xla_device()
    
    dtype = torch.bfloat16

    # mixed_precision_policy = MixedPrecision(param_dtype=dtype, reduce_dtype=dtype, buffer_dtype=dtype)

    # Optimizer
    # Split weights in two groups, one with weight decay and the other not.
    no_decay = ["bias", "LayerNorm.weight", "layer_norm.weight"]
    optimizer_grouped_parameters = [
        {
            "params": [p for n, p in model.named_parameters() if not any(nd in n for nd in no_decay)],
            "weight_decay": args.weight_decay,
        },
        {
            "params": [p for n, p in model.named_parameters() if any(nd in n for nd in no_decay)],
            "weight_decay": 0.0,
        },
    ] 

    optimizer = torch.optim.AdamW(optimizer_grouped_parameters, lr=args.learning_rate)

    # Scheduler and math around the number of training steps.
    overrode_max_train_steps = False
    num_update_steps_per_epoch = math.ceil(len(train_dataloader) / args.gradient_accumulation_steps)
    if args.rank==0:
        print(f"Number of update steps per epoch {num_update_steps_per_epoch}")
    if args.max_train_steps is None:
        args.max_train_steps = args.num_train_epochs * num_update_steps_per_epoch
        overrode_max_train_steps = True

    lr_scheduler = get_scheduler(
        name=args.lr_scheduler_type,
        optimizer=optimizer,
        num_warmup_steps=args.num_warmup_steps * args.gradient_accumulation_steps,
        num_training_steps=args.max_train_steps * args.gradient_accumulation_steps,
    )

    start = time.time()
    #device = torch.device(f"cuda:{args.local_rank}")

    for epoch in range(args.num_train_epochs):

        model.train()
        total_steps=0
        fsdp_loss = torch.zeros(2).to(device)

        for _, batch in enumerate(tqdm(train_dataloader,disable=not (args.rank==0))):

            batch = {k: v.to(device) for k, v in batch.items()}
            output = model(**batch)
            loss = output["loss"]
            loss.backward()
            fsdp_loss[0] += loss.item()
            fsdp_loss[1] += len(batch["input_ids"])
        
            xm.optimizer_step(optimizer)
            xm.mark_step()
            #optimizer.step()
            lr_scheduler.step()
            optimizer.zero_grad()
            total_steps += 1
            if args.max_steps is not None and total_steps > args.max_steps:
                break
             

        torch.distributed.all_reduce(fsdp_loss, op=torch.distributed.ReduceOp.SUM)
        train_loss = fsdp_loss[0] / fsdp_loss[1]
        train_ppl = torch.exp(train_loss)

        if args.rank==0:
            print(f"******{epoch=}: {train_ppl=} {train_loss=}******")
        

        model.eval()
        eval_loss = 0
        fsdp_eval_loss = torch.zeros(2).to(device)
        for steps, batch in enumerate(tqdm(eval_dataloader,disable=not (args.rank==0))):
            batch = {k: v.to(device) for k, v in batch.items()}
            with torch.no_grad():
                outputs = model(**batch)
            loss = outputs["loss"]

            fsdp_eval_loss[0] += loss.item()
            fsdp_eval_loss[1] += len(batch["input_ids"])
            xm.mark_step()
            if args.max_steps is not None and steps > args.max_steps:
                break

        torch.distributed.all_reduce(fsdp_eval_loss, op=torch.distributed.ReduceOp.SUM)
        eval_loss = fsdp_eval_loss[0] / fsdp_eval_loss[1]
        eval_ppl = torch.exp(eval_loss)

        if args.rank==0:
            print(f"*******{epoch=}: {eval_ppl=} {eval_loss=}*******")

        if args.max_steps is not None and total_steps > args.max_steps:
            break

    if args.rank == 0:
        print("Training done!")
    dist.barrier()



import torch.distributed as dist
def main():
    dist.init_process_group(backend="xla")
    args, _ = parse_arge()
    args.local_rank = xm.get_local_ordinal()
    args.rank = xm.get_ordinal()
    args.world_size = xm.xrt_world_size() 
    training_function(args)


if __name__ == "__main__":
    main()

