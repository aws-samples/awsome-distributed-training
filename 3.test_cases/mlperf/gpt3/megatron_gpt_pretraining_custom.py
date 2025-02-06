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
import hydra

from omegaconf.omegaconf import OmegaConf, open_dict
from pytorch_lightning import Trainer
from pytorch_lightning.callbacks.timer import Timer
from pytorch_lightning.trainer.connectors.checkpoint_connector import CheckpointConnector

from nemo.collections.nlp.models.language_modeling.megatron_gpt_model import MegatronGPTModel
from nemo.collections.nlp.parts.nlp_overrides import (
    GradScaler,
    MegatronHalfPrecisionPlugin,
    PipelineMixedPrecisionPlugin,
)
from nemo.core.config import hydra_runner
from nemo.utils import logging
from nemo.utils.exp_manager import StatelessTimer, exp_manager, TimingCallback, NeMoModelCheckpoint
try:
    # TODO: remove this import after we transition to >=23.02 container
    from lightning_lite.plugins.environments import TorchElasticEnvironment
except ImportError:
    from pytorch_lightning.plugins.environments import TorchElasticEnvironment

import custom_optimizer  # noqa (this import just registers a new optimizer)
import custom_schedulers  # noqa (this import just registers a new LR scheduler)
from custom_callbacks import CustomCallback, MetricsLogger, \
    DistributedCheckpointIO, \
    EpochTimingCallback, CustomNLPDDPStrategy, CustomMegatronGPTModel, \
    configure_pre_validation_training_loop, setup_auxiliary_loggers
from mlperf_logger import mllogger
from types import MethodType
from pytorch_lightning.callbacks import ModelCheckpoint

# TODO: file PR with these resolvers to NeMo
# The best way would be to implement an ast resolver that allows only evaluating binary operators and literals
OmegaConf.register_new_resolver("add", lambda x,y: x + y)
OmegaConf.register_new_resolver("ceil_div", lambda x,y: (x + y - 1)//y)
OmegaConf.register_new_resolver("floor_div", lambda x,y: x//y)
OmegaConf.register_new_resolver("div", lambda x,y: x/y)
OmegaConf.register_new_resolver("if", lambda x,y,z: y if x else z)
OmegaConf.register_new_resolver("lt", lambda x,y: x < y)
OmegaConf.register_new_resolver("eq", lambda x,y: x == y)
OmegaConf.register_new_resolver("neq", lambda x,y: x != y)

@hydra.main(config_path="conf", config_name="megatron_gpt_config_custom", version_base="1.2")
def main(cfg) -> None:
    OmegaConf.resolve(cfg)

    # TODO this is to mute the log from distributed, there must be more elegant way to do so
    import logging as base_logging
    base_logging.getLogger("torch.distributed.distributed_c10d").setLevel(logging.WARNING)

    logging.info("\n\n************** Experiment configuration ***********")
    logging.info(f'\n{OmegaConf.to_yaml(cfg)}')

    megatron_amp_o2 = cfg.model.get('megatron_amp_O2', False)
    with_distributed_adam = cfg.model.optim.get('name') == 'distributed_fused_adam'

    plugins = [
        DistributedCheckpointIO(cfg.model.custom.get('load_directly_on_device', False),
                                cfg.model.custom.get('use_two_stage_loading', 0),
                                cfg.model.custom.get('use_two_stage_cpu_transfer', 1))
    ]
    strategy = CustomNLPDDPStrategy(
        use_dist_ckpt=cfg.model.custom.get('use_distributed_checkpointing', 1),
        no_ddp_communication_hook=True,  # we don't use DDP for async grad allreduce
        gradient_as_bucket_view=cfg.model.gradient_as_bucket_view,
        find_unused_parameters=False,
    )
    if cfg.trainer.precision in [16, 'bf16']:
        scaler = None
        if cfg.trainer.precision == 16:
            scaler = GradScaler(
                init_scale=cfg.model.get('native_amp_init_scale', 2 ** 32),
                growth_interval=cfg.model.get('native_amp_growth_interval', 1000),
                hysteresis=cfg.model.get('hysteresis', 2),
            )
        if megatron_amp_o2 and not with_distributed_adam:
            plugins.append(MegatronHalfPrecisionPlugin(precision=cfg.trainer.precision, device='cuda', scaler=scaler))
        else:
            plugins.append(PipelineMixedPrecisionPlugin(precision=cfg.trainer.precision, device='cuda', scaler=scaler))

    #    if cfg.get('cluster_type', None) == 'BCP':
    #        plugins.append(TorchElasticEnvironment())
    plugins.append(TorchElasticEnvironment())

    custom_callback = CustomCallback(cfg)
    trainer = Trainer(plugins=plugins, strategy=strategy, **cfg.trainer, callbacks=[custom_callback])

    exp_manager(trainer, cfg.exp_manager)
    setup_auxiliary_loggers()

    # update resume from checkpoint found by exp_manager
    if cfg.model.resume_from_checkpoint is not None:
        resume_from_checkpoint = cfg.model.resume_from_checkpoint
    else:
        resume_from_checkpoint = trainer._checkpoint_connector.resume_from_checkpoint_fit_path

    logging.info(f'Resuming training from checkpoint: {resume_from_checkpoint}')

    trainer._checkpoint_connector = CheckpointConnector(trainer, resume_from_checkpoint=resume_from_checkpoint)
    # Override timer callback to a stateless one
    for idx, callback in enumerate(trainer.callbacks):
        # TODO: conversion to StatelessTimer happens in exp_manager since 23.01, we can remove it then
        if isinstance(callback, Timer):
            trainer.callbacks[idx] = StatelessTimer(cfg.trainer.max_time,)
        if isinstance(callback, TimingCallback):
            trainer.callbacks[idx] = EpochTimingCallback(callback.timer)
        if isinstance(callback, NeMoModelCheckpoint):
            # In the exp_manager, configure_checkpoint: https://github.com/NVIDIA/NeMo/blob/main/nemo/utils/exp_manager.py#L1022 method
            # is called which manipulates the configuration parameters before creating the NemoModelCheckpoint instance.
            # Using the workaround below to avoid that
            def custom_on_validation_end(self, trainer: "pl.Trainer", pl_module: "pl.LightningModule"):
                pass
            def custom_on_train_end(self, trainer: "pl.Trainer", pl_module: "pl.LightningModule"):
                if trainer.fast_dev_run:
                    return None
                monitor_candidates = self._monitor_candidates(trainer)
                ModelCheckpoint._save_last_checkpoint(self, trainer, monitor_candidates)
                # Call parent on_train_end() to save the -last checkpoint
                ModelCheckpoint.on_train_end(self, trainer, pl_module)
            if cfg.exp_manager.get('checkpoint_callback_params', None) and (cfg.exp_manager.checkpoint_callback_params.get('every_n_epochs', 1) == 0):
                trainer.callbacks[idx].on_validation_end = MethodType(custom_on_validation_end, trainer.callbacks[idx])
            if cfg.exp_manager.get('checkpoint_callback_params', None) and cfg.exp_manager.checkpoint_callback_params.get('save_last', False):
                trainer.callbacks[idx].on_train_end = MethodType(custom_on_train_end, trainer.callbacks[idx])

    # hydra interpolation does not work here as the interpolation key is lost when PTL saves hparams
    with open_dict(cfg):
        cfg.model.precision = cfg.trainer.precision

    model = CustomMegatronGPTModel(cfg.model, trainer)

    trainer.loggers.append(MetricsLogger(trainer, model, custom_callback, cfg.model.custom.target_log_ppl,
                                         cfg.model.custom.extend_run_evals))
    if cfg.model.custom.pre_validate:
        configure_pre_validation_training_loop(trainer)
    trainer.fit(model)


if __name__ == '__main__':
    mllogger.start(key=mllogger.constants.INIT_START)
    main()

