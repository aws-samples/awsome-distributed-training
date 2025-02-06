# Copyright (c) 2022-2023, NVIDIA CORPORATION.  All rights reserved.
#
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
from contextlib import redirect_stdout, nullcontext
from functools import partial
from itertools import chain
from os import environ
from typing import Any, Dict, Optional, Callable, Mapping

import torch
from megatron.core import parallel_state
from nemo.core.optim import MainParamsOptimizerWrapper
from pytorch_lightning import LightningModule

from dist_checkpointing import LocalNonpersitentObject
from dist_checkpointing.mapping import ShardedTensor
from dist_checkpointing.dict_utils import dict_map_with_key, \
    dict_list_map_inplace, inspect_types
from dist_checkpointing.optimizer import optim_state_to_sharding_state, \
    get_param_id_to_sharded_param_map, make_sharded_optimizer_tensor
from custom_optimizer import CustomDistributedFusedAdam

TE_LAYERS_MAP = {
    "self_attention.layernorm_qkv.layer_norm_weight": "input_layernorm.weight",
    "self_attention.layernorm_qkv.layer_norm_bias": "input_layernorm.bias",
    "layernorm_mlp.layer_norm_weight": "post_attention_layernorm.weight",
    "layernorm_mlp.layer_norm_bias": "post_attention_layernorm.bias",
    "layernorm_mlp.fc1_weight": "mlp.dense_h_to_4h.weight",
    "layernorm_mlp.fc1_bias": "mlp.dense_h_to_4h.bias",
    "layernorm_mlp.fc2_weight": "mlp.dense_4h_to_h.weight",
    "layernorm_mlp.fc2_bias": "mlp.dense_4h_to_h.bias",
    "self_attention.layernorm_qkv.weight": "self_attention.query_key_value.weight",
    "self_attention.layernorm_qkv.bias": "self_attention.query_key_value.bias",
    "self_attention.proj.weight": "self_attention.dense.weight",
    "self_attention.proj.bias": "self_attention.dense.bias",
}

TENSOR_PARALLEL_LAYERS_AXIS_MAP = {
    'self_attention.query_key_value.weight': 0,
    'self_attention.query_key_value.bias': 0,
    'self_attention.dense.weight': 1,
    'mlp.dense_h_to_4h.weight': 0,
    'mlp.dense_h_to_4h.bias': 0,
    'mlp.dense_4h_to_h.weight': 1,
}


def generate_unified_state_dict(checkpoint: Optional[dict], model: LightningModule):
    optimizer = model.optimizers(use_pl_optimizer=False)
    assert isinstance(optimizer, (MainParamsOptimizerWrapper, CustomDistributedFusedAdam)), type(optimizer)

    if checkpoint is None:
        checkpoint = {}

    # TODO: make proper integration in NeMo (checkpoint dump format should be defined in model classes)

    if isinstance(model.model, list):
        for i in range(len(model.model)):
            parallel_state.set_virtual_pipeline_model_parallel_rank(i)
            checkpoint[f'model{i}'] = model.model[i].module.state_dict_for_save_checkpoint(keep_vars=True)
            checkpoint[f'model{i}'] = generate_model_unified_state_dict(checkpoint[f'model{i}'], model.model[i].module, model.cfg)
        parallel_state.set_virtual_pipeline_model_parallel_rank(0)

    else:
        checkpoint['state_dict'] = {}
        checkpoint['model0'] = model.model.module.state_dict_for_save_checkpoint(keep_vars=True)
        checkpoint['model0'] = generate_model_unified_state_dict(checkpoint['model0'], model.model.module, model.cfg)

    if isinstance(optimizer, MainParamsOptimizerWrapper):
        checkpoint['optimizer_states'] = [generate_optimizer_unified_state_dict(checkpoint, optimizer)]
    else:
        checkpoint['optimizer_states'] = [optimizer.state_dict_for_save_checkpoint(True, checkpoint)]
    return checkpoint


def _get_layer_offset(cfg, gpt_model):
    num_layers_per_model = gpt_model.language_model.encoder.get_num_layers(cfg.num_layers)

    if parallel_state.get_virtual_pipeline_model_parallel_world_size() is not None:
        assert num_layers_per_model % parallel_state.get_virtual_pipeline_model_parallel_world_size() == 0, (
            'num_layers_per_stage must be divisible by ' 'virtual_pipeline_model_parallel_size'
        )

        assert gpt_model.language_model.encoder.model_type.value != 2, f'virtual pipeline parallel currently only supported for GPT'
        num_layers_per_model = num_layers_per_model // parallel_state.get_virtual_pipeline_model_parallel_world_size()
        offset = parallel_state.get_virtual_pipeline_model_parallel_rank() * (
            cfg.num_layers // parallel_state.get_virtual_pipeline_model_parallel_world_size()
        ) + (parallel_state.get_pipeline_model_parallel_rank() * num_layers_per_model)
    else:
        offset = parallel_state.get_pipeline_model_parallel_rank() * num_layers_per_model
    return offset


def generate_model_unified_state_dict(state_dict, gpt_model, cfg):
    mpu = parallel_state
    offset = _get_layer_offset(cfg, gpt_model)

    def maybe_make_sharded_pp_tp_tensor(layer_key, tensor, prefix=''):
        if not layer_key.startswith('layers.'):
            return tensor
        layer_key_split = layer_key.split('.')
        local_layer_offset = int(layer_key_split[1])
        global_layer_offset = local_layer_offset + offset
        layer_name = '.'.join(layer_key_split[2:])
        sharded_offsets = [(0, global_layer_offset, cfg.num_layers)]  # PP sharding
        assert global_layer_offset < cfg.num_layers, (global_layer_offset, cfg.num_layers)
        layer_name = TE_LAYERS_MAP.get(layer_name, layer_name)
        extra_state_suf = '._extra_state'
        if layer_name.endswith(extra_state_suf):
            return LocalNonpersitentObject(tensor)
        if layer_name in TENSOR_PARALLEL_LAYERS_AXIS_MAP:
            tp_axis = TENSOR_PARALLEL_LAYERS_AXIS_MAP[layer_name]
            # TP sharding
            sharded_offsets.append([tp_axis + 1, mpu.get_tensor_model_parallel_rank(),
                                    mpu.get_tensor_model_parallel_world_size()])
            replica_id = (0, 0, mpu.get_data_parallel_rank())
        else:
            replica_id = (mpu.get_tensor_model_parallel_rank(), 0, mpu.get_data_parallel_rank())
        sharded_key = '.'.join(layer_key_split[:1] + [layer_name])
        return ShardedTensor.from_rank_offsets(
            prefix + sharded_key,
            tensor,
            *sharded_offsets,
            replica_id=replica_id,
            prepend_axis_num=1  # for PP sharding
        )

    dict_map_with_key(partial(maybe_make_sharded_pp_tp_tensor, prefix='language_model.encoder.'),
                      state_dict['language_model']['encoder'])

    if gpt_model.pre_process:
        state_dict['language_model']['embedding']['word_embeddings']['weight'] = ShardedTensor.from_rank_offsets(
            'language_model.embedding.word_embeddings.weight',
            state_dict['language_model']['embedding']['word_embeddings']['weight'],
            (0, mpu.get_tensor_model_parallel_rank(), mpu.get_tensor_model_parallel_world_size()),
            replica_id=(0, 0, mpu.get_data_parallel_rank()),
            allow_shape_mismatch=True
        )
        state_dict['language_model']['embedding']['position_embeddings']['weight'] = ShardedTensor.from_rank_offsets(
            'language_model.embedding.position_embeddings.weight',
            state_dict['language_model']['embedding']['position_embeddings']['weight'],
            replica_id=(mpu.get_tensor_model_parallel_rank(), 0, mpu.get_data_parallel_rank()),
        )

    if gpt_model.post_process and not gpt_model.pre_process:
        state_dict['word_embeddings_for_head']['weight'] = ShardedTensor.from_rank_offsets(
            f'language_model.embedding.word_embeddings.weight',  # reuse
            state_dict['word_embeddings_for_head']['weight'],
            (0, mpu.get_tensor_model_parallel_rank(), mpu.get_tensor_model_parallel_world_size()),
            replica_id=(0, 1, mpu.get_data_parallel_rank()),  # 2 copies
            allow_shape_mismatch=True,
        )
    if gpt_model.post_process:
        state_dict['language_model']['encoder']['final_layernorm.weight'] = ShardedTensor.from_rank_offsets(
            f'language_model.encoder.final_layernorm.weight',
            state_dict['language_model']['encoder']['final_layernorm.weight'],
            replica_id=(mpu.get_tensor_model_parallel_rank(), 0, mpu.get_data_parallel_rank()),
        )
        state_dict['language_model']['encoder']['final_layernorm.bias'] = ShardedTensor.from_rank_offsets(
            f'language_model.encoder.final_layernorm.bias',
            state_dict['language_model']['encoder']['final_layernorm.bias'],
            replica_id=(mpu.get_tensor_model_parallel_rank(), 0, mpu.get_data_parallel_rank()),
        )

    dict_list_map_inplace(lambda t: t.detach() if isinstance(t, torch.Tensor) else t, state_dict)
    return state_dict


# TODO: make proper integration in NeMo (this function should be an optimizer class method)
def generate_optimizer_unified_state_dict(model_state_dict, optimizer):
    def init_opt_state(opt):
        for group in opt.param_groups:
            for p in group['params']:
                if len(opt.state[p]) == 0:
                    opt.state[p]['exp_avg'] = torch.zeros_like(p.data)
                    opt.state[p]['exp_avg_sq'] = torch.zeros_like(p.data)
    init_opt_state(optimizer)  # TODO: consider running init only during checkpoint loading
    state_dict = optimizer.state_dict()

    id_to_sharded_param_map = get_param_id_to_sharded_param_map(
        model_state_dict,
        chain.from_iterable(g for g in optimizer.float16_groups))

    # Convert fp32_from_fp16_params
    assert len(state_dict['fp32_from_fp16_params']) == len(state_dict['optimizer']['param_groups'])

    def get_safe(param_id):
        try:
            return id_to_sharded_param_map[param_id]
        except KeyError as e:
            raise ValueError(f'Param id {param_id} does not match any model sharded param') from e

    state_dict['fp32_from_fp16_params'] = [
        [
            make_sharded_optimizer_tensor(get_safe(param_id), fp32_param,
                                          prefix=f'optimizer.state.fp32_from_fp16')
            for param_id, fp32_param in zip(state_group['params'], fp32_group)
        ]
        for fp32_group, state_group in zip(state_dict['fp32_from_fp16_params'],
                                           state_dict['optimizer']['param_groups'])
    ]

    # Convert state
    optim_state_to_sharding_state(state_dict['optimizer'], id_to_sharded_param_map)
    return state_dict
