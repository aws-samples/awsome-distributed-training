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
from collections import defaultdict
from itertools import chain
from pathlib import Path
from typing import Union, Iterable, List, Tuple

import numpy as np
import torch

from .core import CheckpointingConfig, maybe_load_config, save_config
from .dict_utils import dict_list_map_inplace, merge, nested_values, diff, \
    map_reduce
from .mapping import ShardedStateDict, StateDict, ShardedTensor, \
    CheckpointingException, is_main_replica
from .strategies.base import SaveShardedStrategy, LoadShardedStrategy, \
    SaveCommonStrategy, LoadCommonStrategy, StrategyAction, get_default_strategy
from .utils import extract_sharded_tensors_or_nonpersistent, extract_sharded_tensors

COMMON_STATE_FNAME = 'common.pt'

logger = logging.getLogger(__name__)


def load(sharded_state_dict: ShardedStateDict,
         checkpoint_dir: str,
         sharded_strategy: Union[LoadShardedStrategy, None] = None,
         common_strategy: Union[LoadCommonStrategy, None] = None) -> StateDict:
    """Loading entrypoint.

    Arguments:
        sharded_state_dict: state dict of the existing model populated with
            ShardedTensors. Used as a mapping to determine which parts of
            global tensors stored in the checkpoint should be loaded.
        checkpoint_dir: directory with the checkpoint
        sharded_strategy: configures loading behavior for sharded tensors
        common_strategy: configures loading behavior for common data
    """
    if common_strategy is not None:
        raise NotImplementedError('The only supported common strategy is torch')

    checkpoint_dir = Path(checkpoint_dir)
    common_state_dict = load_common_state_dict(checkpoint_dir)
    if not sharded_state_dict:
        return common_state_dict

    saved_config = maybe_load_config(checkpoint_dir)
    if saved_config is None:
        raise CheckpointingException(f'{checkpoint_dir} is not a distributed checkpoint')

    sharded_state_dict, _ = extract_sharded_tensors_or_nonpersistent(sharded_state_dict)
    sharded_state_dict, nonpersistent_state_dict = extract_sharded_tensors(sharded_state_dict)
    dict_list_map_inplace(lambda o: o.unwrap(), nonpersistent_state_dict)
    merge(common_state_dict, nonpersistent_state_dict)

    validate_sharding_integrity(nested_values(sharded_state_dict))

    if sharded_strategy is None:
        sharded_strategy = get_default_strategy(StrategyAction.LOAD_SHARDED,
                                                saved_config.sharded_backend,
                                                saved_config.sharded_backend_version)
    else:
        # TODO: implement consistency checks here
        pass
    loaded_state_dict = sharded_strategy.load(sharded_state_dict, checkpoint_dir)

    merge(common_state_dict, loaded_state_dict)
    return common_state_dict


def load_common_state_dict(checkpoint_dir: str):
    return torch.load(Path(checkpoint_dir) / COMMON_STATE_FNAME)


def save(sharded_state_dict: ShardedStateDict,
         checkpoint_dir: str,
         sharded_strategy: Union[SaveShardedStrategy, None] = None,
         common_strategy: Union[SaveCommonStrategy, None] = None):
    """Saving entrypoint.

    Extracts ShardedTensors from the given state dict. Rank 0 saves the
    "regular" part of the checkpoint to common torch file.
    The ShardedTensors are saved according to a strategy specified by the
    config.

    Arguments:
        sharded_state_dict: state dict of the populated with
            ShardedTensors. Used as a mapping to determine how local tensors
            should be saved as global tensors in the checkpoint.
        checkpoint_dir: directory to save the checkpoint to
        sharded_strategy: configures sharded tensors saving behavior and backend
        common_strategy: configures common data saving behavior and backend
    """
    checkpoint_dir = Path(checkpoint_dir)

    if torch.distributed.get_rank() == 0:
        if not checkpoint_dir.exists():
            raise CheckpointingException(
                f'Checkpoint destination directory does not exist: {checkpoint_dir}')

        if next(checkpoint_dir.iterdir(), None) is not None:
            raise CheckpointingException(
                f'Checkpoint destination directory ({checkpoint_dir}) is not empty')

    if common_strategy is not None:
        raise NotImplementedError('The only supported common strategy is torch')

    if sharded_strategy is None:
        sharded_strategy = get_default_strategy(StrategyAction.SAVE_SHARDED, 'zarr', 1)


    sharded_state_dict, state_dict = extract_sharded_tensors_or_nonpersistent(sharded_state_dict)
    sharded_state_dict, _ = extract_sharded_tensors(sharded_state_dict)
    sharded_tensors = list(nested_values(sharded_state_dict))
    validate_sharding_integrity(sharded_tensors)

    _save_common_dict(state_dict, checkpoint_dir)

    sharded_strategy.save(sharded_tensors, checkpoint_dir)
    save_config(CheckpointingConfig(sharded_strategy.backend, sharded_strategy.version),
                checkpoint_dir)


# TODO: implement it as common torch strategy
def _save_common_dict(state_dict: StateDict, checkpoint_dir: Path,
                      validate_consistency: bool = False):
    if torch.distributed.get_rank() == 0:
        torch.save(state_dict, checkpoint_dir / COMMON_STATE_FNAME)
    if validate_consistency:
        torch.distributed.barrier()
        if not torch.distributed.get_rank() == 0:
            rank_0_state_dict = torch.load(checkpoint_dir / COMMON_STATE_FNAME)
            # TODO: implement checking consistency with rank 0 common dict on other ranks
            print(diff(state_dict, rank_0_state_dict))


def validate_sharding_integrity(sharded_tensors: Iterable[ShardedTensor]):
    sharding = [ten.without_data() for ten in sharded_tensors]
    all_sharding = [None] * torch.distributed.get_world_size()
    torch.distributed.all_gather_object(all_sharding, sharding)
    if torch.distributed.get_rank() != 0:
        return

    key_shardings = defaultdict(list)
    for rank, rank_shardings in enumerate(all_sharding):
        for sharding in rank_shardings:
            key_shardings[sharding.key].append((rank, sharding))
    for key, shardings in key_shardings.items():
        _validate_sharding_for_key(shardings)


def _validate_sharding_for_key(rank_sharding: List[Tuple[int, ShardedTensor]]):
    global_shape = rank_sharding[0][1].global_shape
    local_shape = rank_sharding[0][1].local_shape
    dtype = rank_sharding[0][1].dtype
    has_flattened_range = rank_sharding[0][1].flattened_range is not None
    for rank, sharding in rank_sharding:
        assert sharding.dtype == dtype, (sharding.dtype, dtype)
        assert sharding.global_shape == global_shape, (sharding.global_shape, global_shape)
        assert sharding.local_shape == local_shape, (sharding.local_shape, local_shape)
        assert (sharding.flattened_range is not None) == has_flattened_range, ((sharding.flattened_range is not None), has_flattened_range)

    shard_access_cnt = _compute_shards_access(rank_sharding)
    if has_flattened_range:
        map_reduce(rank_sharding,
                   lambda x: x[1].global_offset,
                   lambda x: x[1],
                   _validate_sharding_for_key_flattened)
    else:
        if not torch.all(shard_access_cnt == 1):
            logger.error(
                f'Invalid access pattern for {rank_sharding[0][1]}: {shard_access_cnt}')
            raise CheckpointingException(
                f'Invalid access pattern for {rank_sharding[0][1]}')


def _compute_shards_access(rank_sharding):
    def chunk_offset(sharding):
        assert len(sharding.global_offset) == len(sharding.local_shape) + sharding.prepend_axis_num
        return tuple(chain(
            (off for off in sharding.global_offset[:sharding.prepend_axis_num]),
            (off // sh for off, sh in
             zip(sharding.global_offset[sharding.prepend_axis_num:], sharding.local_shape))
        ))

    shard_access_cnt = torch.zeros(rank_sharding[0][1].axis_fragmentations, dtype=torch.int, device='cpu')
    for rank, sharding in rank_sharding:
        if is_main_replica(sharding.replica_id):
            shard_access_cnt[chunk_offset(sharding)] += 1
        # TODO: consider validating different replicas too
    return shard_access_cnt


def _validate_sharding_for_key_flattened(tensors_by_shard):
    all_slices = []
    local_shape = tensors_by_shard[0].local_shape
    for sharding in tensors_by_shard:
        assert sharding.local_shape == local_shape
        sharding: ShardedTensor
        if not is_main_replica(sharding.replica_id):
            # TODO: this checks only saving (and loading replica_id=0) consistency
            continue

        all_slices.append((sharding.flattened_range.start, sharding.flattened_range.stop))

    starts, stops = map(np.asarray, zip(*sorted(all_slices)))
    if (starts[0] != 0
            or stops[-1] != np.product(local_shape)
            or not np.all(starts[1:] == stops[:-1])):
        logger.error(f'Flattened ranges dont cover the whole shard {tensors_by_shard[0]}. Ranges: {(starts, stops)}')
        raise CheckpointingException(f'Flattened ranges dont cover the whole shard {tensors_by_shard[0]}')
