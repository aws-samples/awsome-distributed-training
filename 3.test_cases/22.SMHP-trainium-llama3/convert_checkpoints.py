import argparse
import json
import os
import re

import torch
import torch_xla.utils.serialization as xser

from neuronx_distributed.pipeline.partition import create_partitions

def get_hf_to_nxd_model_keys(kv_replication=True, is_gqa=True):
    if kv_replication:
        keys_hf_to_nxd = {
            "q_proj.weight": "qkv_proj.weight_q",
            "k_proj.weight": "qkv_proj.weight_k",
            "v_proj.weight": "qkv_proj.weight_v",
        }
    elif is_gqa:
        keys_hf_to_nxd = {
            "q_proj.weight": "q_proj.weight",
            "k_proj.weight": "k_proj.weight",
            "v_proj.weight": "v_proj.weight",
        }
    else:
        keys_hf_to_nxd = {
            "q_proj.weight": "qkv_proj.weight",
            "k_proj.weight": "qkv_proj.weight",
            "v_proj.weight": "qkv_proj.weight",
        }
    keys_nxd_to_hf = {v:k for k,v in keys_hf_to_nxd.items()}
    return keys_hf_to_nxd, keys_nxd_to_hf


def is_qkv_weight(name):
    return "q_proj" in name or "k_proj" in name or "v_proj" in name or "qkv_proj" in name


def get_weight_key(keys_hf_to_nxd, keys_nxd_to_hf, name, hf_to_nxd):
    if not is_qkv_weight(name):
        return name
    
    keys = keys_hf_to_nxd if hf_to_nxd else keys_nxd_to_hf
    return ".".join(name.split(".")[:-2]) + "." + keys[".".join(name.split(".")[-2:])]


def merge_llama_tp_checkpoints(args):
    full_model = {}
    with open(args.config, "r") as f:
        config = json.load(f)
    q_heads = config["num_attention_heads"]
    kv_heads = config["num_key_value_heads"]
    head_dim = config["hidden_size"] // q_heads
    is_gqa = q_heads != kv_heads
    keys_hf_to_nxd, keys_nxd_to_hf = get_hf_to_nxd_model_keys(args.kv_size_multiplier > 1 , is_gqa)

    for tp_rank in range(args.tp_size):
        for pp_rank in range(args.pp_size):
            if args.load_xser:
                partial_state = load_partial_xser(args, tp_rank, pp_rank)
            else:
                partial_state = load_partial_no_xser(args, tp_rank, pp_rank)
            if args.model_key is not None and args.model_key in partial_state:
                partial_state = partial_state[args.model_key]
            for name, param in partial_state.items():
                if (is_qkv_weight(name) or "o_proj" in name) and args.kv_size_multiplier > 1:
                    # qkv_proj would be a key if we are using the QKVLinear layer
                    partition_dim = 1 if "o_proj" in name else 0
                    name = get_weight_key(keys_hf_to_nxd, keys_nxd_to_hf, name, False)

                    if name not in full_model:
                        full_model[name] = []
                    
                    full_model[name].append(param)
                    if tp_rank != (args.tp_size - 1):
                        continue
                    
                    full_weight = torch.cat(full_model[name], dim=partition_dim)
                    if "k" in name or "v" in name:
                        # If kv_multiplier is set, the kv heads are repeated. So we need to
                        # take only the first chunk
                        full_model[name] = torch.chunk(full_weight, args.kv_size_multiplier)[0].detach().clone()
                    else:
                        # Since we do the replication of KV heads, the Q heads are placed as:
                        # Q0Q1Q8Q9...Q2Q3Q10Q11...
                        # Hence when creating the merged checkpoint, we need to bring the Q heads and o_proj in order.
                        if "o_proj" in name:
                            # The shuffling is same for both o_proj and q, but o_proj is sharded on column.
                            # Hence to reuse the same shuffling code, we just transpose, do the shuffling and 
                            # transpose back
                            full_weight = torch.transpose(full_weight, 0, 1)
                        weights = full_weight.reshape(q_heads, head_dim, -1)
                        weights_shape = weights.size()
                        weights = weights.reshape(
                            -1, q_heads // (kv_heads * args.kv_size_multiplier), head_dim, weights_shape[-1]
                        )
                        weight_splits = []
                        indicies = torch.arange(0, args.tp_size // kv_heads) * kv_heads
                        for i in range(kv_heads):
                            weight_splits.append(weights[indicies + i].reshape(-1, weights_shape[-1]))
                        full_weight = torch.cat(weight_splits, dim=0)
                        full_model[name] = torch.transpose(full_weight, 0, 1).detach().clone() if "o_proj" in name else full_weight.detach().clone()
                elif "qkv_proj" in name and not is_gqa:
                    partition_size = config["hidden_size"] // args.tp_size
                    q,k,v = torch.split(param, partition_size, dim=0)
                    q_name = name.replace("qkv", "q")
                    k_name = name.replace("qkv", "k")
                    v_name = name.replace("qkv", "v")
                    for name, weight in zip([q_name, k_name, v_name], [q,k,v]):
                        if name not in full_model:
                            full_model[name] = []
                        full_model[name].append(weight)
                        if tp_rank == (args.tp_size - 1):
                            full_weight = torch.cat(full_model[name], dim=0)
                            full_model[name] = full_weight.detach().clone()
                elif (
                    "embed_tokens" in name
                    or is_qkv_weight(name)
                    or "o_proj" in name
                    or "down_proj" in name
                    or "lm_head" in name
                ):
                    partition_dim = 1 if ("o_proj" in name or "down_proj" in name) else 0
                    name = get_weight_key(keys_hf_to_nxd, keys_nxd_to_hf, name, False)
                    if name not in full_model:
                        full_model[name] = []
                    full_model[name].append(param)
                    if tp_rank == (args.tp_size - 1):
                        full_weight = torch.cat(full_model[name], dim=partition_dim)
                        full_model[name] = full_weight.detach().clone()
                elif "gate_up_proj" in name:
                    partition_dim = 0
                    dim_size = param.size()[partition_dim] // 2
                    gate_proj_name = name.replace("gate_up_proj", "gate_proj")
                    up_proj_name = name.replace("gate_up_proj", "up_proj")
                    gate_proj_weight = param.narrow(partition_dim, 0, dim_size).detach().clone()
                    up_proj_weight = param.narrow(partition_dim, dim_size, dim_size).detach().clone()
                    if gate_proj_name not in full_model:
                        full_model[gate_proj_name] = []
                    if up_proj_name not in full_model:
                        full_model[up_proj_name] = []
                    full_model[gate_proj_name].append(gate_proj_weight)
                    full_model[up_proj_name].append(up_proj_weight)
                    if tp_rank == (args.tp_size - 1):
                        full_gate_proj_weight = torch.cat(full_model[gate_proj_name], dim=partition_dim)
                        full_up_proj_weight = torch.cat(full_model[up_proj_name], dim=partition_dim)
                        full_model[gate_proj_name] = full_gate_proj_weight
                        full_model[up_proj_name] = full_up_proj_weight
                else:
                    if name not in full_model:
                        full_model[name] = param
    return full_model


def translate_llama_full_state_dict_to_tp(
    full_state, tp_size, tp_rank, pp_size, pp_rank, partitions, kv_size_multiplier, config
):
    partial_state = {}
    q_heads = config["num_attention_heads"]
    kv_heads = config["num_key_value_heads"]
    head_dim = config["hidden_size"] // q_heads

    is_gqa = q_heads != kv_heads
    keys_hf_to_nxd, keys_nxd_to_hf = get_hf_to_nxd_model_keys(kv_size_multiplier > 1 , is_gqa)

    for name, full_p in full_state.items():
        ##################### PP Slice #########################################
        # Embedding only in first PP
        if pp_rank != 0 and "embed_tokens" in name:
            continue
        # LMhead and final layer norm only in last PP rank
        if pp_rank != pp_size - 1 and ("lm_head" in name or "model.norm.weight" in name):
            continue
        if "layers" in name:
            layer_idx = int(name.split(".")[2])
            pre_layer_cut = int(partitions[pp_rank - 1].split(".")[2]) if pp_rank > 0 else -10000000
            current_layer_cut = int(partitions[pp_rank].split(".")[2]) if pp_rank < pp_size - 1 else 10000000
            if layer_idx <= pre_layer_cut or layer_idx > current_layer_cut:
                continue

        ##################### TP Slice #########################################
        if (is_qkv_weight(name) or "o_proj" in name) and kv_size_multiplier > 1:
            name = get_weight_key(keys_hf_to_nxd, keys_nxd_to_hf, name, True)
            if "weight_k" in name or "weight_v" in name:
                repeated_kv = full_p.repeat(kv_size_multiplier, 1)

                dim_size = repeated_kv.size()[0]
                assert dim_size % tp_size == 0, "0th dim after KV replication is not divisible by tp_size"
                partition_size = dim_size // tp_size
                with torch.no_grad():
                    to_load = repeated_kv.narrow(0, tp_rank * partition_size, partition_size).detach().clone()
                    # Cloning the tensor is really important, since we have performed slice and reshape operations.
                    # These operations are just views and if we don't clone, we would end up saving the entire tensor
                    partial_state[name] = to_load.detach().clone()
            else:
                # When GQAQKV linear with kv_multiplier is used, we need to reshuffle the order of Q heads 
                # so they interact with the right KV heads. Now since the heads are shuffled, we have to
                # shuffle the o_proj rows since that translates the heads to hidden dim
                if "o_proj" in name:
                    # The shuffling is same for both o_proj and q, but o_proj is sharded on column.
                    # Hence to reuse the same shuffling code, we just transpose, do the shuffling and 
                    # transpose back
                    full_p = torch.transpose(full_p, 0, 1)
                weights = full_p.reshape(q_heads, head_dim, -1)
                weights_shape = weights.size()
                weights = weights.reshape(
                    -1, q_heads // (kv_heads * kv_size_multiplier), head_dim, weights_shape[-1]
                )
                weight_splits = []
                indicies = torch.arange(0, kv_heads) * tp_size // kv_heads
                for i in range(tp_size // kv_heads):
                    weight_splits.append(weights[indicies + i])
                weights = torch.cat(weight_splits, dim=0)
                with torch.no_grad():
                    to_load = weights[tp_rank].reshape(-1, weights_shape[-1])
                    if "o_proj" in name:
                        to_load = torch.transpose(to_load, 0, 1)
                    # Cloning the tensor is really important, since we have performed slice and reshape operations.
                    # These operations are just views and if we don't clone, we would end up saving the entire tensor
                    partial_state[name] = to_load.detach().clone()

        elif (
            "embed_tokens" in name
            or is_qkv_weight(name)
            or "o_proj" in name
            or "down_proj" in name
            or "lm_head" in name
        ):
            # parallel embedding or ColumnParallelLinear, parallel on 0th dim
            # RowParallelLinear parallel on 1st dim
            partition_dim = 1 if ("o_proj" in name or "down_proj" in name) else 0
            dim_size = full_p.size()[partition_dim]
            assert dim_size % tp_size == 0, "vocab size is not divisiable"
            partition_size = dim_size // tp_size
            with torch.no_grad():
                to_load = full_p.narrow(partition_dim, tp_rank * partition_size, partition_size)
                partial_state[name] = to_load.detach().clone()
        elif "gate_proj" in name or "up_proj" in name:
            # ColumnParallelLinear
            partition_dim = 0
            dim_size = full_p.size()[partition_dim]
            assert dim_size % tp_size == 0, "vocab size is not divisiable"
            partition_size = dim_size // tp_size
            with torch.no_grad():
                to_load = full_p.narrow(partition_dim, tp_rank * partition_size, partition_size).detach().clone()
            token = "gate_proj" if "gate_proj" in name else "up_proj"
            updated_name = name.replace(token, "gate_up_proj")
            if updated_name in partial_state:
                if token == "gate_proj":
                    partial_state[updated_name] = torch.cat([to_load, partial_state[updated_name]], dim=0).detach().clone()
                else:
                    partial_state[updated_name] = torch.cat([partial_state[updated_name], to_load], dim=0).detach().clone()
            else:
                partial_state[updated_name] = to_load.detach().clone()
        else:
            # no TP
            partial_state[name] = full_p
    return partial_state

def coalesce_qkv(state_dict, config, tp_degree):

    for i in range(config["num_hidden_layers"]):
        q = state_dict.pop(f"model.layers.{i}.self_attn.q_proj.weight")
        k = state_dict.pop(f"model.layers.{i}.self_attn.k_proj.weight")
        v = state_dict.pop(f"model.layers.{i}.self_attn.v_proj.weight")
        partition_size = config["hidden_size"] // tp_degree
        tp_partititons = []
        for tp_rank in range(tp_degree):
            q_split = q.narrow(0, tp_rank * partition_size, partition_size).detach().clone()
            k_split = k.narrow(0, tp_rank * partition_size, partition_size).detach().clone()
            v_split = v.narrow(0, tp_rank * partition_size, partition_size).detach().clone()
            tp_partititons.append(torch.cat([q_split, k_split, v_split], dim=0))

        state_dict[f"model.layers.{i}.self_attn.qkv_proj.weight"] = torch.cat(tp_partititons, dim=0)
    
    return state_dict


# Save Load Entries
def load_full(args):
    full_state = torch.load(args.input_dir)
    return full_state


def determine_input_filename(args, tp_rank, pp_rank, xser):
    if xser:
        old_api_filename = os.path.join(args.input_dir, "tp_rank_{:02d}_pp_rank_{:02d}".format(tp_rank, pp_rank))
    else:
        old_api_filename = os.path.join(
            args.input_dir, "tp_rank_{:02d}_pp_rank_{:02d}".format(tp_rank, pp_rank), "checkpoint.pt"
        )

    new_api_filename = os.path.join(
        args.input_dir, "dp_rank_00_tp_rank_{:02d}_pp_rank_{:02d}.pt".format(tp_rank, pp_rank)
    )

    if os.path.exists(old_api_filename):
        return old_api_filename

    if os.path.exists(new_api_filename):
        return new_api_filename

    raise RuntimeError(f"Error: neither {old_api_filename} nor {new_api_filename} exist")


def determine_output_filename(args, tp_rank, pp_rank, xser):
    return os.path.join(args.output_dir, "model", "dp_rank_00_tp_rank_{:02d}_pp_rank_{:02d}.pt".format(tp_rank, pp_rank))


def load_partial_xser(args, tp_rank, pp_rank):
    filename = determine_input_filename(args, tp_rank, pp_rank, 1)
    partial_state = xser.load(filename)
    return partial_state


def load_partial_no_xser(args, tp_rank, pp_rank):
    filename = determine_input_filename(args, tp_rank, pp_rank, 0)
    partial_state = torch.load(filename)
    return partial_state


def save_full(args, full_model):
    save_path = args.output_dir
    os.makedirs(save_path, exist_ok=True)
    if os.path.isdir(save_path):
        save_path = os.path.join(save_path, "checkpoint.pt")
    print(f"Saving full checkpoint to {save_path}")
    torch.save(full_model, save_path)


def save_partial_xser(args, partial_state, tp_rank, pp_rank):
    filename = determine_output_filename(args, tp_rank, pp_rank, 1)
    os.makedirs(args.output_dir + "/model", exist_ok=True)
    print(f"Saving to {filename}")
    xser.save(partial_state, filename)


def save_partial_no_xser(args, partial_state, tp_rank, pp_rank):
    filename = determine_output_filename(args, tp_rank, pp_rank, 0)
    os.makedirs(args.output_dir + "/model", exist_ok=True)
    print(f"Saving to {filename}")
    torch.save(partial_state, filename)


# Convertion Entries
def convert_from_xser(args):
    for tp_rank in range(args.tp_size):
        for pp_rank in range(args.pp_size):
            partial_state = load_partial_xser(args, tp_rank, pp_rank)
            save_partial_no_xser(args, partial_state, tp_rank, pp_rank)


def convert_to_xser(args):
    for tp_rank in range(args.tp_size):
        for pp_rank in range(args.pp_size):
            partial_state = load_partial_no_xser(args, tp_rank, pp_rank)
            save_partial_xser(args, partial_state, tp_rank, pp_rank)


def convert_from_full_model(args):
    full_state = load_full(args)
    layer_name_pattern = r"^(model\.layers\.\d+)"
    model_layer_names = sorted(
        list(
            set(
                [
                    re.match(layer_name_pattern, key).group(1)
                    for key in full_state.keys()
                    if re.match(layer_name_pattern, key)
                ]
            )
        ),
        key=lambda x: int(re.search(r"\d+", x).group()),
    )
    partitions = create_partitions(args.pp_size, model_layer_names)
    print(f"pipeline_cuts {partitions}")
    with open(args.config, "r") as f:
        config = json.load(f)
    if args.coalesce_qkv:
        full_state = coalesce_qkv(full_state, config, args.tp_size)

    for tp_rank in range(args.tp_size):
        for pp_rank in range(args.pp_size):
            partial_state = translate_llama_full_state_dict_to_tp(
                full_state,
                args.tp_size,
                tp_rank,
                args.pp_size,
                pp_rank,
                partitions,
                args.kv_size_multiplier,
                config,
            )
            if args.save_xser:
                save_partial_xser(args, partial_state, tp_rank, pp_rank)
            else:
                save_partial_no_xser(args, partial_state, tp_rank, pp_rank)


def convert_to_full_model(args):
    full_model = merge_llama_tp_checkpoints(args)
    save_full(args, full_model)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input_dir", type=str, required=True, help="Path to input model/weights")
    parser.add_argument("--output_dir", type=str, required=True, help="Path to save converted model/weights")
    parser.add_argument(
        "--model_key", type=str, default="model", help="Key of the model state dict in the checkpoint object"
    )
    parser.add_argument("--tp_size", type=int, default=1, help="Tensor Parallel degree for the model")
    parser.add_argument("--pp_size", type=int, default=1, help="Pipeline Parallel degree for the model")
    parser.add_argument("--n_layers", type=int, default=0, help="Number of Layers")
    parser.add_argument("--coalesce_qkv", type=bool, default=False, help="whether to coalesce qkv for llama7B/13B")
    parser.add_argument("--load_xser", type=bool, default=False, help="Load from xser saved checkpoints")
    parser.add_argument("--save_xser", type=bool, default=False, help="Save with xser")
    parser.add_argument(
        "--convert_from_xser", action="store_true", help="Convert xser saved checkpoint to normal torch checkpoint"
    )
    parser.add_argument(
        "--convert_to_xser", action="store_true", help="Convert normal torch checkpoint to xser checkpoint"
    )
    parser.add_argument("--convert_from_full_model", action="store_true", help="Convert full model to sharded model")
    parser.add_argument("--convert_to_full_model", action="store_true", help="Convert sharded model to full model")
    parser.add_argument(
        "--kv_size_multiplier", type=int, default=1, help="Factor by which the KV heads were replicated"
    )
    parser.add_argument("--config", type=str, help="Config.json")

    args, _ = parser.parse_known_args()
    if args.convert_from_full_model:
        convert_from_full_model(args)
    elif args.convert_to_full_model:
        convert_to_full_model(args)
    elif args.convert_from_xser:
        convert_from_xser(args)
    elif args.convert_to_xser:
        convert_to_xser(args)
