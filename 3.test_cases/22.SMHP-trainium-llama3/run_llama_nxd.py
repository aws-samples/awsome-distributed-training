# coding=utf-8
# Copyright (c) 2019 NVIDIA CORPORATION. All rights reserved.
# Copyright 2018 The Google AI Language Team Authors and The HuggingFace Inc. team.
# Modifications Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import math
import os
import random
import time

import numpy as np
import torch
import torch.distributed as dist
import torch_xla.core.xla_model as xm
import torch_xla.distributed.xla_multiprocessing as xmp
import transformers.modeling_utils as modeling_utils
from transformers import LlamaConfig

import neuronx_distributed as nxd
from neuronx_distributed.parallel_layers import (
    ColumnParallelLinear,
    ParallelEmbedding,
    RowParallelLinear,
    mappings,
    parallel_state,
)
from neuronx_distributed.parallel_layers.parallel_state import (
    get_data_parallel_rank,
    get_data_parallel_size,
    get_pipeline_model_parallel_rank,
    get_tensor_model_parallel_rank,
    initialize_model_parallel,
)
# For delayed parameter inititalization
# Check https://pytorch.org/torchdistx/latest/deferred_init.html
try:
    from torchdistx import deferred_init
except ImportError:
    deferred_init = None

from collections import namedtuple

from logger import Logger
from modeling_llama_nxd import (
    CoreAttention,
    LlamaDecoderLayer,
    LlamaForCausalLM,
    LlamaRMSNorm,
    init_weights,
)
from training_utils import (
    Throughput,
    TrainingMetrics,
    create_llama_pretraining_dataset,
    create_partition,
    get_dtype,
    get_learning_rate_scheduler,
    get_param_groups_by_weight_decay,
    get_sin_cos_matrix,
    print_logs,
)

from neuronx_distributed.utils.adamw_fp32_optim_params import AdamW_FP32OptimParams

Metric = namedtuple("Metric", ["name", "value", "units", "additional_data"])


def train_llama(args):
    if dist.get_rank() == 0:
        print(f"args {args}")
    torch.manual_seed(args.seed)
    np.random.seed(args.seed)
    random.seed(args.seed)

    # Set up Llama config
    config = LlamaConfig.from_pretrained(args.training_config)
    config.use_cache = False
    config.return_dict = False
    config.sequence_parallel_enabled = args.use_sequence_parallel > 0
    config.qkv_linear = args.qkv_linear > 0
    config.selective_checkpoint_enabled = args.use_selective_checkpoint > 0
    config.kv_shared_group_size = args.kv_replicator
    config.max_position_embeddings = max(config.max_position_embeddings, args.seq_len)
    if args.num_layer != -1:
        config.num_hidden_layers = args.num_layer
    if args.hidden_size != -1:
        config.hidden_size = args.hidden_size

    # Create model with different options
    # Either deferred_init or meta device initialization will be required to avoid host OOM for 70B model
    if args.use_meta_device_init > 0:
        model_init_config = {
            "meta_device_init": True,
            "param_init_fn": init_weights,
        }
    else:
        model_init_config = None
    nxd_config = nxd.neuronx_distributed_config(
        tensor_parallel_size=args.tensor_parallel_size,
        pipeline_parallel_size=args.pipeline_parallel_size,
        pipeline_config={
            "transformer_layer_cls": LlamaDecoderLayer,
            "num_microbatches": args.num_microbatches,
            "output_loss_value_spec": (True, False),
            "input_names": ["input_ids", "attention_mask", "labels"],
            "auto_partition": True,
            "trace_file_path": args.trace_file_path,
            "param_init_fn": None,
            "leaf_module_cls": [LlamaRMSNorm.__name__],
            "autowrap_modules": [mappings],
            "use_zero1_optimizer": args.use_zero1_optimizer > 0,
            "use_optimizer_wrapper": True,
        },
        optimizer_config={
            "zero_one_enabled": args.use_zero1_optimizer > 0,
            "grad_clipping": True,
            "max_grad_norm": 1.0,
        },
        sequence_parallel=args.use_sequence_parallel,
        activation_checkpoint_config=CoreAttention if args.use_selective_checkpoint > 0 else "full",
        model_init_config=model_init_config,
    )

    def get_model(config):
        if args.use_deferred_init > 0 and deferred_init is not None:
            model = deferred_init.deferred_init(LlamaForCausalLM, config)
        else:
            model = LlamaForCausalLM(config)
        # Here we make sure we use the same sine and cosine matrices for all layers.
        # Making use of same tensors would make the CSE algorithm eliminate the lookup call
        # from layers, keeping only lookup from first layer.
        with torch.no_grad():
            cos, sin = get_sin_cos_matrix(config)
            for layer in model.model.layers:
                layer.self_attn.rotary_emb.cos_cached = cos
                layer.self_attn.rotary_emb.sin_cached = sin
        num_params = sum([np.prod(p.size()) for p in model.parameters()])
        if dist.get_rank() == 0:
            print(f"# total parameters: {num_params}")
            print(f"model config {config}")
        return model

    # Create NxD model
    model = nxd.initialize_parallel_model(nxd_config, get_model, config)
    world_size = parallel_state.get_data_parallel_size()
    # model_dtype = get_dtype(model)

    param_groups = get_param_groups_by_weight_decay(model)

    opt_cls = AdamW_FP32OptimParams if args.use_fp32_optimizer > 0 else torch.optim.AdamW
    optimizer = nxd.initialize_parallel_optimizer(
        nxd_config, opt_cls, param_groups, lr=args.lr, betas=(args.beta1, args.beta2), weight_decay=args.weight_decay
    )

    dp_rank = get_data_parallel_rank()
    dp_size = get_data_parallel_size()
    tp_rank = get_tensor_model_parallel_rank()
    pp_rank = get_pipeline_model_parallel_rank()

    lr_scheduler = get_learning_rate_scheduler(optimizer, args)

    train_dataloader, _ = create_llama_pretraining_dataset(
        args.training_dir, args.train_batch_size, dp_size, dp_rank, args.seed
    )

    print("Creating sample dataloader finised")

    # Only print/logging on the last PP rank of the first PP group
    # Since loss is only in the last PP rank
    should_print = pp_rank == args.pipeline_parallel_size - 1 and dp_rank == 0 and tp_rank == 0

    logger = Logger(args, should_print)

    total_steps = 0
    resume_batch_idx = None

    def get_loading_tag(args):
        if args.loading_step == "-1":
            return "-1"

        if args.loading_step == "latest_if_exists":
            return None if nxd.has_checkpoint(args.checkpoint_dir) else "-1"

        return f"step_{args.loading_step}"

    tag = get_loading_tag(args)
    if tag != "-1":
        user_content = nxd.load_checkpoint(
            args.checkpoint_dir,
            tag=tag,
            model=model,
            optimizer=optimizer,
            scheduler=lr_scheduler,
        )
        if user_content is not None:
            resume_batch_idx = user_content["batch_idx"]
            total_steps = user_content["total_steps"]
    elif args.pretrained_weight==1: # 1 (exist) or 0
        user_content = nxd.load_checkpoint(
           args.checkpoint_dir,
           tag="pretrained_weight",
           model=model,
           optimizer=None,
           scheduler=None,
        )
        if args.use_zero1_optimizer > 0:
            # We need to do init_zero1 here since after loading model weights, we
            # need to sync the new params with base optimzier params.
            optimizer.optimizer.init_zero()


    epoch = 0
    throughput = Throughput(args.train_batch_size, dp_size, 1, 10, args.logging_interval)
    metric_writer = TrainingMetrics(args.metrics_file)
    print("--------TRAINING CONFIG----------")
    print(args)
    print("--------MODEL CONFIG----------")
    print(config)
    print("---------------------------------")
    # "Model configuration": config,
    param_contents = {
        "Model": config.model_type,
        "World size": xm.xrt_world_size(),
        "Data parallel degree": world_size,
        "Batch size": args.train_batch_size,
        "Total steps": args.max_steps,
        "Seed": args.seed,
        # "Optimizer": str(optimizer),
        "Warmup steps": args.warmup_steps,
        "Dataset": os.path.basename(os.path.normpath(args.training_dir)),
        # "Environment variables": {
        #     variable: value
        #     for variable, value in os.environ.items()
        #     if variable.startswith("NEURON") or variable.startswith("XLA")
        # }
    }
    if should_print:
        metric_writer.store_parameters(param_contents)
    while True:
        if torch.distributed.get_rank() == 0:
            print(f"Epoch {epoch}")
        for batch_idx, batch in enumerate(train_dataloader):
            if resume_batch_idx is not None and batch_idx <= resume_batch_idx:
                if torch.distributed.get_rank() == 0:
                    print(f"skipping batch {batch_idx}")
                continue
            start = time.time()
            input_ids = batch["input_ids"]
            attention_mask = batch["attention_mask"]
            labels = batch["labels"]
            # Enavle auto-mix-precision if needed
            with torch.autocast(enabled=args.use_amp > 0, dtype=torch.bfloat16, device_type="cuda"):
                # Calling model.run_train instead of model forward to use the PP runtime
                loss = model.run_train(
                    input_ids=input_ids,
                    attention_mask=attention_mask,
                    labels=labels,
                )
            total_steps += 1
            optimizer.step()
            global_norm = optimizer.grad_norm  # Global norm before clipping
            optimizer.zero_grad()
            lr_scheduler.step()
            if should_print:
                if total_steps % args.logging_interval == 0:
                    xm.add_step_closure(
                        logger.log,
                        (
                            total_steps,
                            loss.detach(),
                            global_norm,
                            lr_scheduler.get_lr()[0],
                            input_ids.detach(),
                            throughput,
                            start,
                        ),
                    )
            xm.mark_step()
            # Saving checkpoints
            if (args.checkpoint_freq > 0) and (total_steps % args.checkpoint_freq == 0):
                nxd.save_checkpoint(
                    args.checkpoint_dir,
                    tag=f"step_{total_steps}",
                    model=model,
                    optimizer=optimizer,
                    scheduler=lr_scheduler,
                    user_content={"total_steps": total_steps, "batch_idx": batch_idx, "cli_args": args.__dict__},
                    use_xser=args.save_load_xser,
                    num_kept_ckpts=args.num_kept_checkpoint,
                    async_save=args.async_checkpoint_saving,
                )
            if total_steps >= args.max_steps:
                break

        if total_steps >= args.max_steps:
            break
        epoch += 1

    final_time = time.time()
    time_diff = final_time - start
    # record aggregate & final statistics in the metrics file
    additional_data = {"Epoch": epoch, "Global step": total_steps}
    min_throughput_index = math.ceil(10 / args.logging_interval)
    if len(logger.throughputs) > min_throughput_index:
        throughputs_to_average = logger.throughputs[min_throughput_index:]
    else:
        throughputs_to_average = logger.throughputs
    average_throughput = (
        round(sum(throughputs_to_average) / len(throughputs_to_average), 4) if len(logger.throughputs) > 0 else None
    )
    metric_data = [
        Metric("Final loss", loss.detach().item() if loss is not None else None, "", additional_data),
        Metric(
            "Time to train",
            round(time_diff / 60, 4),
            "minutes",
            additional_data,
        ),
        Metric(
            "Average throughput",
            average_throughput,
            "seq/s",
            additional_data,
        ),
        Metric(
            "Peak throughput",
            max(logger.throughputs) if len(logger.throughputs) > 0 else None,
            "seq/s",
            additional_data,
        ),
    ]
    if should_print:
        metric_writer.store_metrics(metric_data)
    print("Training finished successfully")


def _mp_fn(index, args):
    train_llama(args)
    xm.rendezvous("_mp_fn finished")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--num_microbatches", type=int, default=8, help="num_microbatches")
    parser.add_argument("--tensor_parallel_size", type=int, default=8, help="tensor_parallel_size")
    parser.add_argument("--num_layer", type=int, default=-1, help="override model number of layers")
    parser.add_argument("--hidden_size", type=int, default=-1, help="override model model hidden size")
    parser.add_argument("--train_batch_size", type=int, default=16, help="batch size")
    parser.add_argument("--pipeline_parallel_size", type=int, default=1, help="PP size")
    parser.add_argument("--kv_replicator", type=int, default=1, help="KV replication size")
    parser.add_argument("--seq_len", type=int, default=4096, help="PP size")
    parser.add_argument("--training_dir", type=str, default=None)
    parser.add_argument("--training_config", type=str, default=None)
    parser.add_argument("--trace_file_path", type=str, default=None)
    parser.add_argument("--tb_dir", type=str, default="")
    parser.add_argument("--max_steps", type=int, default=100, help="max steps")
    parser.add_argument("--checkpoint_freq", type=int, default=100000, help="save checkpoint freq")
    parser.add_argument("--checkpoint_dir", type=str, default=None)
    parser.add_argument(
        "--loading_step",
        type=str,
        default="-1",
        help='load from step, "-1" means no load, "latest_if_exists" can be used to load latest checkpoint',
    )
    parser.add_argument(
        "--num_kept_checkpoint",
        type=int,
        default=-1,
        help="number of checkpoints kept, old checkpoint will get deleted",
    )
    parser.add_argument("--save_load_xser", type=int, default=1, help="save/load with xla serialization")
    parser.add_argument("--pretrained_weight", type=int, default=None, help="Load dir of pretrained weight")
    parser.add_argument(
        "--async_checkpoint_saving",
        type=int,
        default=0,
        help="whether to use asynchronous checkpoint saving. 1 for using, 0 for not using. Default is 0",
    )
    parser.add_argument("--metrics_file", type=str, default="results.json", help="training metrics results file")
    # optimization
    opt_grp = parser.add_argument_group(title="optimization", description="arguments for optimization")
    opt_grp.add_argument("--weight_decay", default=0.01, type=float, help="weight decay")
    opt_grp.add_argument("--beta1", default=0.9, type=float, help="beta1 parameter for Adam optimizer")
    opt_grp.add_argument("--beta2", default=0.95, type=float, help="beta2 parameter for Adam optimizer")
    opt_grp.add_argument("--use_fp32_optimizer", default=0, type=int, help="use_fp32_optimizer")
    opt_grp.add_argument("--use_zero1_optimizer", default=0, type=int, help="use_zero1_optimizer")
    opt_grp.add_argument("--seed", default=1234, type=int, help="random seed")
    opt_grp.add_argument("--use_amp", default=0, type=int, help="use amp data")
    opt_grp.add_argument("--use_deferred_init", default=0, type=int, help="use torchdistx deferred initialization")
    opt_grp.add_argument("--use_meta_device_init", default=0, type=int, help="use meta device initialization")
    opt_grp.add_argument(
        "--use_selective_checkpoint", default=0, type=int, help="enable selective activation checkpointing"
    )
    opt_grp.add_argument("--use_sequence_parallel", default=1, type=int, help="enable sequence parallelism")
    opt_grp.add_argument("--qkv_linear", default=0, type=int, help="Use QKV Linear module")

    # learning rate
    lr_grp = parser.add_argument_group(title="lr", description="arguments for learning rate schedule")
    lr_grp.add_argument("--lr", type=float, default=None, help="Initial learning rate.")
    lr_grp.add_argument("--warmup_steps", type=int, default=None, help="number of warmup_steps")
    lr_grp.add_argument("--constant_steps", type=int, default=None, help="number of warmup_steps")
    lr_grp.add_argument(
        "--min_lr",
        type=float,
        default=None,
        help="Minumum value for learning rate. The scheduler" "clip values below this threshold.",
    )
    lr_grp.add_argument("--logging_interval", type=int, default=1, help="number of warmup_steps")

    args, _ = parser.parse_known_args()
    # Workaround for NaNs seen with transformers version >= 4.21.0
    # https://github.com/aws-neuron/aws-neuron-sdk/issues/593
    if os.environ.get("XLA_USE_BF16") or os.environ.get("XLA_DOWNCAST_BF16") or args.use_amp > 0:
        modeling_utils.get_parameter_dtype = lambda x: torch.bfloat16

    if os.environ.get("WORLD_SIZE"):
        dist.init_process_group("xla")
        _mp_fn(0, args)
    else:
        xmp.spawn(_mp_fn, args=(args,))
