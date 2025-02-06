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

import logging
from copy import deepcopy
from dataclasses import replace
from itertools import chain
from typing import Dict

import torch
from apex.contrib.optimizers.distributed_fused_adam import DistributedFusedAdam
from megatron.core import parallel_state
from nemo.core.optim.distributed_adam import MegatronDistributedFusedAdam
from nemo.core.optim.optimizers import AVAILABLE_OPTIMIZERS

from dist_checkpointing import ShardedTensor, LocalNonpersitentObject
from dist_checkpointing.dict_utils import merge
from dist_checkpointing.mapping import StateDict
from dist_checkpointing.optimizer import get_param_id_to_sharded_param_map, \
    optim_state_to_sharding_state, make_sharded_optimizer_tensor

logger = logging.getLogger(__name__)


class CustomDistributedFusedAdam(MegatronDistributedFusedAdam):
    """ Adds distributed checkpointing capabilities to the Distributed Optimizer. """

    def __init__(self, *args, **kwargs):
        logger.info('Using CustomDistributedFusedAdam optimizer')
        super().__init__(*args, **kwargs)

    def state_dict_for_save_checkpoint(self, distributed_checkpoint=False, model_sharded_state_dict=None):
        assert distributed_checkpoint, f'{self.__class__.__name__}.state_dict_for_save_checkpoint requires distributed checkpointing'
        assert model_sharded_state_dict is not None, f'{self.__class__.__name__}.state_dict_for_save_checkpoint requires passing model checkpoint with ShardedTensors'

        id_to_sharded_param_map = get_param_id_to_sharded_param_map(
            model_sharded_state_dict,
            chain.from_iterable(g['params'] for g in self.param_groups))

        # Convert state
        optim_sd_kwargs = {}
        if hasattr(self, '_state_dict_v1'):
            # In ~08/29/23 Apex introduced new state_dict format, need to use the old one.
            # This flag can become a default once old Apex compatiblity is not necessary.
            optim_sd_kwargs['v1_format'] = True
            try:
                # pre 9/1/23 args
                state_dict = self.state_dict(gather_on_root=False, v1_format=True)
            except TypeError:
                # post 9/1/23 args
                state_dict = self.state_dict(gather_on_root=False, state_dict_format=1)
        else:
            state_dict = self.state_dict(gather_on_root=False)
        if state_dict is None:
            state_dict = {}
        state_dict = self.optim_state_to_sharding_state(state_dict, id_to_sharded_param_map)

        # Fp32 optimizer
        self.add_fp32_sharding_state(state_dict, model_sharded_state_dict)

        return state_dict

    def load_state_dict(self, state_dict):
        if 'gathered_states' in state_dict:
            # regular checkpoint
            return super().load_state_dict(state_dict)

        # Resuming from non-distributed optimizer case. TODO: handle this in more general way (if we want to support it in NeMo)
        if 'optimizer' in state_dict:
            state_dict['param_groups'] = merge(state_dict['optimizer']['param_groups'], state_dict['param_groups'])

        # Copy `step` from non-distributed optimizer. TODO: handle this in more general way (if we want to support it in NeMo)
        if 'step' not in state_dict['state'] and 'step' in state_dict['param_groups'][0]:
            state_dict['state']['step'] = state_dict['param_groups'][0].pop('step')

        # Deallocate existing buckets state (will be overwritten) to free some
        # cuda memory and aggregate bucket state from fragments on cpu
        for bucket in self.state['buckets']:
            for field in ('exp_avg_shard', 'exp_avg_sq_shard', 'params_shard', 'param_remainders_shard'):
                field_tensor = getattr(bucket, field)
                if field_tensor is None:
                    setattr(bucket, field, None)
                else:
                    assert field_tensor.is_cuda, (field, field_tensor.device)
                    # Aggregate bucket states on cpu
                    setattr(bucket, field, torch.empty_like(field_tensor, device='cpu'))


        optim_state = state_dict['state']
        assert optim_state['buckets'] == self.state['buckets'], \
            'When loading from distributed checkpoint, buckets should be' \
            ' wrapped with LocalNonpersitentObject'

        # TODO: maybe run consistency validation here
        # Copies relevant fragments data from checkpoint into the buckets.
        # Check `make_sharded_fragment_data` docs for further explanation
        # (here we "reverse" that method).
        for param_id, fragments_data in optim_state['fragments_local_data'].items():
            for fragment_id, fragment_data in fragments_data.items():
                fragment_data: torch.Tensor
                fragment: DistributedFusedAdam.ParameterFragment = optim_state[param_id]['fragments'][fragment_id]
                bucket = optim_state['buckets'][fragment.bucket_id]

                bucket.exp_avg_shard[slice(*fragment.shard_range)] = fragment_data['exp_avg_shard']
                bucket.exp_avg_sq_shard[slice(*fragment.shard_range)] = fragment_data['exp_avg_sq_shard']

                if 'params_shard' in fragment_data:
                    bucket.params_shard[slice(*fragment.shard_range)] = fragment_data['params_shard']
                    assert 'param_remainders_shard' not in fragment_data, fragment_data.keys()
                else:
                    assert bucket.params_shard is None, f'bucket.params_shard should be None, got: {bucket.params_shard}'
                    assert 'param_remainders_shard' in fragment_data, fragment_data.keys()

                if 'param_remainders_shard' in fragment_data:
                    _, rem = split_fp32(fragment_data['param_remainders_shard'])
                    bucket.param_remainders_shard[slice(*fragment.shard_range)] = rem

        # `fragments_local_data` was needed only to separate raw fragments data
        del optim_state['fragments_local_data']

        self.update_fp32_hyperparameters(state_dict)
        if hasattr(self, '_state_dict_v1'):
            state_dict['format'] = 1
        super().load_state_dict(state_dict)

        # We can't send bucket tensors to cuda earlier because `super()` copies all tensors (would OOM)
        for bucket in self.state['buckets']:
            for field in ('exp_avg_shard', 'exp_avg_sq_shard', 'params_shard', 'param_remainders_shard'):
                field_tensor = getattr(bucket, field)
                setattr(bucket, field, field_tensor.cuda() if field_tensor is not None else None)

    def optim_state_to_sharding_state(self, optim_state_dict: StateDict, id_to_sharded_param_map: Dict[int, ShardedTensor]):
        """
        Wraps optimizer states with ShardedTensor based on model params ShardedTensors.

        Args:
            optim_state_dict: regular optimizer state dict
            id_to_sharded_param_map: a map from optimizer param ids to
                corresponding model param ShardedTensors.
                It will be used to create ShardedTensors for optimizer states.
        """
        optim_state = optim_state_dict['state']

        # For each model param we extract relevant data from the buckets,
        # wrap with ShardedTensor and store in `fragments_local_data`
        fragments_local_data = {}
        for param_id, param_state in optim_state.items():
            if not isinstance(param_id, int):
                continue
            fragments_local_data[param_id] = {
                fragment_id: self.make_sharded_fragment_data(id_to_sharded_param_map[param_id], param_id,
                                                             fragment, optim_state['buckets'][fragment.bucket_id])
                for fragment_id, fragment in enumerate(param_state['fragments'])
                if fragment.in_local_shard
            }
        # When loading from checkpoint, we only need raw data from
        # `fragments_local_data`. All fragments and buckets metadata is taken
        # from the existing state (LocalNonpersitentObject).
        new_optim_state = {k: LocalNonpersitentObject(v) for k, v in optim_state.items() if isinstance(k, int)}
        new_optim_state['fragments_local_data'] = fragments_local_data
        new_optim_state['buckets'] = LocalNonpersitentObject(optim_state['buckets'])

        optim_state_dict['state'] = new_optim_state
        optim_state_dict['param_groups'] = deepcopy(optim_state_dict['param_groups'])
        for group in optim_state_dict['param_groups']:
            group['params'] = LocalNonpersitentObject(group['params'])
            # Step is saved to param_group for compatibility with regular optimizer
            group['step'] = optim_state['step']

        return optim_state_dict

    def make_sharded_fragment_data(self, model_param: ShardedTensor, param_id: int,
                                   fragment: DistributedFusedAdam.ParameterFragment,
                                   bucket: DistributedFusedAdam.StateBucket) -> Dict[str, ShardedTensor]:
        """
        Build a ShardedTensor for a given fragment.

        For sharding scheme explanation check: https://github.com/NVIDIA/Megatron-LM/blob/main/docs/distrib_optimizer.md#sharding-scheme
        DistributedFusedAdam.ParameterFragment attributes vs linked doc correspondence:
        - shard_range ~ local_index
        - shard_param_range ~ param_index
        - shard_bucket_range ~ world_index (not relevant here)
        For more details see DistributedFusedAdam docs.

        For each optimizer state field (exp_avg_shard, ...), this method
        extracts relevant data for the given fragment from the bucket
        (with `[slice(*fragment.shard_range)]`) and wraps with a ShardedTensor
        with similar attributes to the given `model_param` one.

        Args:
            model_param: model parameter corresponding to the given `param_id`
            param_id: optimizer param id
            fragment: one of the fragments for given `param_id`
            bucket: a bucket that contains data for the given fragment
        """
        fragment_local_data = {}
        assert param_id == fragment.param_id
        prefix = f'optimizer.state'
        simple_mapping_fields = {
            'exp_avg_shard': 'exp_avg',
            'exp_avg_sq_shard': 'exp_avg_sq',
            'params_shard': 'fp32_from_fp16',
            'param_remainders_shard': 'fp32_from_fp16',
        }

        for field, field_key in simple_mapping_fields.items():
            field_val = getattr(bucket, field)
            if field_val is None:
                continue
            optim_param = field_val[slice(*fragment.shard_range)]
            if field == 'param_remainders_shard':
                # Construct fp32 tensor from model BF16 params and INT16 remainders
                optim_param = merge_fp32(
                    model_param.data.view(-1)[slice(*fragment.shard_param_range)],
                    optim_param
                )
            assert len(model_param.replica_id) == 3, f'Expected replica_id format (TP, PP, DP), got: {replica_id}'
            replica_id = (*model_param.replica_id[:2], 0)
            fragment_local_data[field] = replace(
                model_param,
                key=f'{prefix}.{field_key}.{model_param.key}',
                data=optim_param,
                dtype=optim_param.dtype,
                flattened_range=slice(*fragment.shard_param_range),
                replica_id=replica_id,
            )

        return fragment_local_data

    def add_fp32_sharding_state(self, optim_state_dict, model_sharded_state_dict=None):
        """ Build sharded state dict for the params of FP32 optimizer. """
        if getattr(self, '_fp32_optim', None) is None:
            return
        if not isinstance(self._fp32_optim, torch.optim.AdamW):
            raise NotImplementedError(f'FP32 Optimizer of type {type(self._fp32_optim)} not supported')

        adam_init_state(self._fp32_optim)
        fp32_state_dict = self._fp32_optim.state_dict()  # recompute after state init

        id_to_sharded_param_map = get_param_id_to_sharded_param_map(
            model_sharded_state_dict,
            self._fp32_optim_main_params.keys())

        def get_safe(param_id):
            try:
                return id_to_sharded_param_map[param_id]
            except KeyError as e:
                breakpoint()
                raise ValueError(f'Param id {param_id} does not match any model sharded param') from e

        # FP32 model params
        optim_state_dict['fp32_optim_fp32_params'] = [
            make_sharded_optimizer_tensor(get_safe(param_id), fp32_param,
                                          prefix=f'optimizer.state.fp32_from_fp16')
            for param_id, fp32_param in enumerate(optim_state_dict['fp32_optim_fp32_params'])
        ]

        # FP32 Optimizer state
        optim_state_to_sharding_state(fp32_state_dict,
                                      id_to_sharded_param_map)

        # Since this is a wrapped optimizer, we don't want to store hyperparameters
        # but they must be updated with `update_fp32_hyperparameters` before calling `load_state_dict`
        for group_idx in range(len(fp32_state_dict['param_groups'])):
            # unwrap LocalNonpersitentObject from 'params' ...
            fp32_state_dict['param_groups'][group_idx]['params'] = fp32_state_dict['param_groups'][group_idx]['params'].obj
            # ... and apply it to the whole group
            fp32_state_dict['param_groups'][group_idx] = LocalNonpersitentObject(fp32_state_dict['param_groups'][group_idx])

        optim_state_dict['fp32_optim'] = fp32_state_dict

    def update_fp32_hyperparameters(self, state_dict):
        """ Copy relevant optimizer hyperparameters and step from main optimizer to FP32 one. """
        if 'fp32_optim' not in state_dict:
            return
        for main_group, fp32_group in zip(state_dict['param_groups'], state_dict['fp32_optim']['param_groups']):
            for k, v in main_group.items():
                if k in fp32_group and k != 'params' and fp32_group[k] != v:
                    logger.info(f'Replacing FP32 optimizer hparam {k} with {v} (previous value: {fp32_group[k]})')
                    fp32_group[k] = v
        # Copt step info
        step = state_dict['state']['step']
        for _, param_state in state_dict['fp32_optim']['state'].items():
            param_state['step'] = step


def adam_init_state(opt):
    for group in opt.param_groups:
        for p in group['params']:
            if len(opt.state[p]) == 0:
                opt.state[p]['exp_avg'] = torch.zeros_like(p.data)
                opt.state[p]['exp_avg_sq'] = torch.zeros_like(p.data)


def split_fp32(x):
    assert x.dtype is torch.float, x.dtype
    x = x.clone().detach()
    rem_bf16 = x.unsqueeze(-1).view(torch.int16)
    rem = rem_bf16[..., 0]
    bf16 = rem_bf16[..., 1]
    assert x.shape == rem.shape == bf16.shape, (x.shape, rem.shape, bf16.shape)
    # Round up BF16
    bf16 += torch.where(rem < 0, 1, 0)
    return bf16.view(torch.bfloat16), rem


def merge_fp32(bf16, rem):
    assert bf16.dtype is torch.bfloat16, bf16.dtype
    assert rem.dtype is torch.int16, rem.dtype
    # Round down BF16
    bf16 = bf16.clone().detach()
    bf16 -= torch.where(rem < 0, 1, 0)

    rem_bf16 = torch.stack((rem, bf16.view(torch.int16)), dim=-1)
    x = rem_bf16.view(torch.float32).squeeze(-1)
    assert x.shape == rem.shape == bf16.shape, (x.shape, rem.shape, bf16.shape)
    return x


AVAILABLE_OPTIMIZERS['distributed_fused_adam'] = CustomDistributedFusedAdam  # replace default implementation
