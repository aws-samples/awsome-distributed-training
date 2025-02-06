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


""" 2-stage loading strategies. """
import os
import time
from collections import defaultdict
from itertools import chain
from logging import getLogger, StreamHandler, DEBUG, INFO
from operator import attrgetter, itemgetter

from dataclasses import dataclass
from functools import partial, wraps
from pathlib import Path
from typing import List, Iterable, NamedTuple, Tuple, Optional, Union

import torch

from .tensorstore import _load_from_array
from .zarr import flatten_range
from ..mapping import ShardedTensor, ShardedStateDict, StateDict
from ..dict_utils import dict_list_map_inplace, nested_values, map_reduce
from .base import LoadShardedStrategy

_import_trigger = None


timers = defaultdict(list)

logger = getLogger(__name__)


def timed(verbose=True):
    def timed_dec(fn):
        name = fn.__name__
        @wraps(fn)
        def wrapped(*args, **kwargs):
            if verbose:
                logger.debug(f'{name} init')
            start = time.time()
            ret = fn(*args, **kwargs)
            took = time.time() - start
            if verbose:
                logger.debug(f'{name} took {took}s')
            timers[name].append(took)
            return ret
        return wrapped
    return timed_dec


@dataclass
class _ExtendedShardedTensor:
    global_rank: int
    sharded_tensor_no_data: ShardedTensor
    dist_group_rank: Tuple[int]  # id of distributed group
    dist_group_ranks: Tuple[int]  # id of distributed group
    data_size: Optional[int] = None  # bytes
    loaded_tensor: Optional[torch.Tensor] = None  # filled after loading


def sharded_tensor_chunk_id(sharded_tensor: ShardedTensor):
    return (
        sharded_tensor.key,
        sharded_tensor.global_offset,
    )


class TwoStageDataParallelLoadShardedStrategy(LoadShardedStrategy):
    """ Assumes replica_id of format (TP, PP, DP). """
    def __init__(self, data_parallel_group, cpu_transfer=True):
        super().__init__()

        self.cpu_transfer = cpu_transfer
        self.data_parallel_group_orig = data_parallel_group
        self.data_parallel_group = None if cpu_transfer else data_parallel_group
        self.dp_group_ranks = tuple(sorted(torch.distributed.get_process_group_ranks(data_parallel_group)))
        self.dp_group_rank = torch.distributed.get_rank(self.data_parallel_group_orig)
        self.global_rank = torch.distributed.get_rank()

    def load(self, sharded_state_dict: ShardedStateDict, checkpoint_dir: Path):
        self.maybe_init_gloo_group()
        all_tensors_sorted = self._build_load_plan(sharded_state_dict)

        self._exchange_loaded_tensors(all_tensors_sorted, sharded_state_dict, checkpoint_dir)

        self.summarize_load_times()
        return sharded_state_dict

    def summarize_load_times(self):
        torch.distributed.barrier()
        logger.info('Checkpoint loading finished. Summary:')
        for key, times in sorted(timers.items()):
            if len(times) > 1:
                assert key in ('_distribute_data_to_state_dict', 'load_tensor_from_storage')
                times = [sum(times)]
            max_times = torch.tensor(times, device='cuda')
            avg_times = torch.tensor(times, device='cuda')
            torch.distributed.all_reduce(max_times,
                                         op=torch.distributed.ReduceOp.MAX)
            torch.distributed.all_reduce(avg_times,
                                         op=torch.distributed.ReduceOp.SUM)
            avg_times /= torch.distributed.get_world_size()
            if torch.distributed.get_rank() == 0:
                logger.info(f'{key}: max {max_times[0]}, avg {avg_times[0]}')

    @timed()
    def load_tenors_from_storage(self, checkpoint_dir,
                                 extended_sharded_tensors):
        for ext_tensor in extended_sharded_tensors:
            if not self.filter_tensor_to_load(ext_tensor):
                continue
            ext_tensor.loaded_tensor = _load_from_array(
                ext_tensor.sharded_tensor_no_data, checkpoint_dir,
                load_directly_on_device=False, apply_flattened_range=False)

    @timed(verbose=False)
    def load_tensor_from_storage(self, checkpoint_dir, ext_tensor):
        if self.filter_tensor_to_load(ext_tensor):
            logger.debug(f'_load_from_array({ext_tensor.sharded_tensor_no_data.key}) init')
            ext_tensor.loaded_tensor = _load_from_array(
                ext_tensor.sharded_tensor_no_data, checkpoint_dir,
                load_directly_on_device=False, apply_flattened_range=False)
            logger.debug(f'_load_from_array({ext_tensor.sharded_tensor_no_data.key}) DONE')

    @timed()
    def maybe_init_gloo_group(self):
        if not self.cpu_transfer:
            return
        all_groups = [None] * torch.distributed.get_world_size()
        torch.distributed.all_gather_object(all_groups, self.dp_group_ranks)
        all_groups = set(tuple(sorted(gr)) for gr in all_groups)
        for group_ranks in sorted(all_groups):
            gloo_pg = torch.distributed.new_group(ranks=group_ranks, backend='gloo')
            if self.global_rank in group_ranks:
                self.data_parallel_group = gloo_pg
                assert self.dp_group_rank == torch.distributed.get_rank(self.data_parallel_group)

    def check_backend_compatibility(self, loaded_version):
        pass  # TODO

    def check_version_compatibility(self, loaded_version):
        pass  # TODO

    @timed()
    def _build_load_plan(self, sharded_state_dict: ShardedStateDict) -> List[_ExtendedShardedTensor]:
        global_rank = torch.distributed.get_rank()
        local_ext_tensors = [
            _ExtendedShardedTensor(global_rank, sharded_ten.without_data(),
                                   self.dp_group_rank, self.dp_group_ranks)
            for sharded_ten in nested_values(sharded_state_dict)
        ]
        all_ext_tensors = [None] * torch.distributed.get_world_size()
        torch.distributed.all_gather_object(all_ext_tensors, local_ext_tensors)  # TODO: group=self.dp_group_ranks
        all_ext_tensors = list(chain.from_iterable(all_ext_tensors))
        all_tensors_sorted = self.deduplicate_chunks(all_ext_tensors)
        return all_tensors_sorted

    @timed()
    def deduplicate_chunks(self, ext_tensors: List[_ExtendedShardedTensor]):
        # TODO: instead of this, we might simply all_gather in that group from the start
        ext_tensors = [t for t in ext_tensors if t.dist_group_ranks == self.dp_group_ranks]
        # Group tensors by chunk and then pick the tensor with the lowest rank
        ext_tensors = map_reduce(ext_tensors,
                                 key_fn=lambda ext_t: sharded_tensor_chunk_id(ext_t.sharded_tensor_no_data),
                                 reduce_fn=partial(min, key=attrgetter('dist_group_rank')))
        all_tensors_sorted = list(map(itemgetter(1), sorted(ext_tensors.items())))
        return all_tensors_sorted

    def filter_tensor_to_load(self, ext_tensor: _ExtendedShardedTensor):
        # NOT TRUE! # Every tensor to load should available on DP rank 0
        # non_zero_rank_tensors = [t for t in load_tensors if t.dist_group_rank != 0]
        # assert not non_zero_rank_tensors, non_zero_rank_tensors

        # TODO: here we can assign the loading arbitrarily! For simplicity, rank 0 will load everything
        # return self.dp_group_rank == 0

        return self.dp_group_rank == ext_tensor.dist_group_rank


    @timed()
    def _exchange_loaded_tensors(self, extended_tensors: List[_ExtendedShardedTensor], sharded_state_dict, checkpoint_dir) -> List[_ExtendedShardedTensor]:
        logger.debug(f'_exchange_loaded_tensors, num ten_metas: {len(extended_tensors)}')
        for ext_tensor in extended_tensors:

            src_rank = torch.distributed.get_global_rank(self.data_parallel_group, ext_tensor.dist_group_rank)

            self.load_tensor_from_storage(checkpoint_dir, ext_tensor)

            if self.dp_group_rank == ext_tensor.dist_group_rank:
                exchange_tensor = ext_tensor.loaded_tensor
                if not self.cpu_transfer:
                    exchange_tensor = exchange_tensor.cuda()
            else:
                # TODO: for non-flattened ranges we could reuse the buffer from the start here
                exchange_tensor = torch.empty(ext_tensor.sharded_tensor_no_data.local_shape, device='cpu' if self.cpu_transfer else 'cuda',
                                              dtype=ext_tensor.sharded_tensor_no_data.dtype)

            logger.debug(f'exchange {ext_tensor.sharded_tensor_no_data.key}, {exchange_tensor.shape}({exchange_tensor.numel()}), broadcast({src_rank} -> {self.dp_group_ranks})')
            torch.distributed.broadcast(exchange_tensor,
                                        group=self.data_parallel_group, src=src_rank)
            logger.debug(f'exchange {ext_tensor.sharded_tensor_no_data.key} done')

            ext_tensor.loaded_tensor = exchange_tensor

            self._distribute_data_to_state_dict(ext_tensor, sharded_state_dict)

            # free buffer memory
            ext_tensor.loaded_tensor = None
            exchange_tensor = None

    @timed(verbose=False)
    def _distribute_data_to_state_dict(self, ext_tensor: _ExtendedShardedTensor, sharded_state_dict: ShardedStateDict):
        ext_tensor_key = sharded_tensor_chunk_id(ext_tensor.sharded_tensor_no_data)

        def _fill_in_data(t: Union[ShardedTensor, torch.Tensor]):
            if not isinstance(t, ShardedTensor) or sharded_tensor_chunk_id(t) != ext_tensor_key:
                # already filled-in or key not matching
                return t
            sharded_tensor: ShardedTensor = t
            x = ext_tensor.loaded_tensor
            if sharded_tensor.flattened_range is not None:
                x = flatten_range(sharded_tensor, x)

            # Reuse existing buffer
            sharded_tensor.data.data.copy_(x)
            return sharded_tensor.data

        dict_list_map_inplace(_fill_in_data, sharded_state_dict)
