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

import torch
from nemo.core.optim.lr_scheduler import AVAILABLE_SCHEDULERS, CosineAnnealing

logger = logging.getLogger(__name__)


# TODo: consider using an upstream version when it's merged
class CosineAnnealingExp(CosineAnnealing):
    """
    Setting max_steps_for_lr_sched for this scheduler in the config is experimental and "
    not recommended. The scheduler can use max_steps automatically from "
    trainer.max_steps.
    """

    def __init__(self, optimizer, *, max_steps, min_lr=0, last_epoch=-1, max_steps_for_lr_sched=None, **kwargs):
        super().__init__(optimizer=optimizer, max_steps=max_steps, last_epoch=last_epoch, min_lr=min_lr, **kwargs)

        logger.info(f'Using custom CosineAnnealingExp LR scheduler with {max_steps_for_lr_sched}')
        if max_steps_for_lr_sched:
            self.max_steps = max_steps_for_lr_sched
        # Ignoring constant_steps
        self.decay_steps = self.max_steps - self.warmup_steps

    def get_lr(self):
        _ = super().get_lr()
        new_lrs = self._get_linear_warmup_with_cosine_annealing_lr(self.last_epoch)
        return new_lrs


AVAILABLE_SCHEDULERS['CosineAnnealingExp'] = CosineAnnealingExp
