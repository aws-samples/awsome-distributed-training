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
import os
import time
from argparse import Namespace
from datetime import datetime

import math
from itertools import repeat
from pathlib import Path
from typing import Dict, Any, Optional, Union

import pytorch_lightning
import pytorch_lightning as pl
import torch
from apex.transformer.pipeline_parallel.utils import get_num_microbatches
from megatron.core import parallel_state
from nemo.collections.nlp.data.language_modeling.megatron.data_samplers import \
    MegatronPretrainingSampler
from nemo.collections.nlp.data.language_modeling.megatron.gpt_dataset import \
    _create_ltor_masks_and_position_ids, MockGPTDataset
from nemo.collections.nlp.data.language_modeling.megatron.megatron_batch_samplers import \
    BaseMegatronBatchSampler
from nemo.collections.nlp.models.language_modeling.megatron_gpt_model import \
    MegatronGPTModel
from nemo.collections.nlp.parts.nlp_overrides import NLPDDPStrategy
from nemo.constants import NEMO_ENV_VARNAME_TESTING
from nemo.utils import AppState
from nemo.utils.env_var_parsing import get_envbool
from nemo.utils.exp_manager import TimingCallback, \
    SkipResumeTrainingValidationLoop
from nemo.utils.formatters.base import BaseNeMoFormatter, DebugNeMoFormatter
from nemo.utils.get_rank import is_global_rank_zero
from nemo.utils.timers import NamedTimer
from pytorch_lightning import Callback
from pytorch_lightning.loggers import Logger
from pytorch_lightning.loops import TrainingEpochLoop
from pytorch_lightning.plugins.io import TorchCheckpointIO
from pytorch_lightning.utilities import rank_zero_only
from pytorch_lightning.utilities.cloud_io import get_filesystem
from torch.utils.data import default_collate

import dist_checkpointing
from dist_checkpointing.dict_utils import dict_list_map_outplace
from dist_checkpointing.strategies.tensorstore import \
    TensorStoreLoadShardedStrategy
from dist_checkpointing.strategies.two_stage import \
    TwoStageDataParallelLoadShardedStrategy
from mlperf_logger import mllogger
from unified_checkpointing import generate_unified_state_dict

_PATH = Union[str, Path]

logger = logging.getLogger(__name__)

def compute_consumed_mllog_tokens(trainer, model):
    # TODO: remove AppState
    steps_since_resume = trainer.global_step - model.init_global_step
    gbs = model.cfg.global_batch_size
    # TODO: remove `model_gbs` after ensuring it's the same as `gbs`
    model_gbs = AppState().data_parallel_size * model.cfg.micro_batch_size * get_num_microbatches()
    assert gbs == model_gbs, (gbs, model_gbs)
    consumed_samples = (
        steps_since_resume * gbs
    )
    return int(consumed_samples) * model.cfg.data.seq_length


def run_training_warmup(trainer, warmup_train_steps):
    torch.distributed.barrier()
    start = time.time()
    # Run forward and backward (no optimizer step)
    for i in range(warmup_train_steps):
        trainer.model.lightning_module.training_step(*trainer.model.lightning_module.get_synthetic_input())
    # For GPT `zero_grad` is a noop, but included here for completeness
    trainer.model.lightning_module.zero_grad()
    trainer._logger_connector.reset_results()
    trainer._logger_connector.reset_metrics()
    torch.distributed.barrier()
    logger.info(f'Time spent in run_training_warmup: {time.time() - start}s')


def reset_fp8_state(model):
    """ Sets `fp8_initialized` flag to False in every TE layer which will force reinitialization. """
    logger.info('Forcing FP8 stats reinitialization')

    def reset_fp8(m):
        if hasattr(m, 'fp8_initialized'):
            m.fp8_initialized = False

    models = model.model
    for model in models if isinstance(models, list) else [models]:
         model.apply(reset_fp8)


class CustomCallback(Callback):
    def __init__(self, cfg):
        super().__init__()
        if cfg.model.custom.force_success_status:
            self.status = mllogger.constants.SUCCESS
        else:
            self.status = mllogger.constants.ABORTED
        self.is_target_reached = False
        self.is_run_stop_already_logged = False

        self.tokens_per_block = cfg.trainer.val_check_interval * cfg.model.global_batch_size * cfg.model.encoder_seq_length
        self.iter_after_valid = False

    def set_success_status(self):
        self.status = mllogger.constants.SUCCESS
        self.is_target_reached = True

    @rank_zero_only
    def on_train_epoch_start(self, trainer: "pl.Trainer", pl_module: "pl.LightningModule") -> None:
        mllogger.start(key=mllogger.constants.EPOCH_START,
                       metadata={'epoch_num': compute_consumed_mllog_tokens(trainer, pl_module)}, sync=False)
        mllogger.start(key=mllogger.constants.BLOCK_START,
                       metadata={'first_epoch_num': compute_consumed_mllog_tokens(trainer, pl_module),
                                 'epoch_count': self.tokens_per_block},
                       sync=False)

        return super().on_train_epoch_start(trainer, pl_module)

    @rank_zero_only
    def on_train_epoch_end(self, trainer: "pl.Trainer", pl_module: "pl.LightningModule") -> None:
        mllogger.end(key=mllogger.constants.EPOCH_STOP,
                     metadata={'epoch_num': compute_consumed_mllog_tokens(trainer, pl_module)}, sync=False)
        return super().on_train_epoch_end(trainer, pl_module)

    def on_train_end(self, trainer: "pl.Trainer", pl_module: "pl.LightningModule") -> None:
        self.maybe_log_run_stop(trainer, pl_module)
        return super().on_train_end(trainer, pl_module)

    @rank_zero_only
    def on_validation_start(self, trainer: "pl.Trainer", pl_module: "pl.LightningModule") -> None:
        mllogger.end(key=mllogger.constants.BLOCK_STOP,
                     metadata={'first_epoch_num': compute_consumed_mllog_tokens(trainer, pl_module) - self.tokens_per_block,
                               'epoch_count': self.tokens_per_block},
                     sync=False)
        mllogger.start(key=mllogger.constants.EVAL_START,
                       metadata={'epoch_num': compute_consumed_mllog_tokens(trainer, pl_module)}, sync=False)
        return super().on_validation_start(trainer, pl_module)

    def on_validation_end(self, trainer: "pl.Trainer", pl_module: "pl.LightningModule") -> None:
        mllogger.end(key=mllogger.constants.EVAL_STOP,
                     metadata=dict(epoch_num=compute_consumed_mllog_tokens(trainer, pl_module)), sync=False)
        if self.is_target_reached:
            self.maybe_log_run_stop(trainer, pl_module)
        self.iter_after_valid = True
        return super().on_validation_end(trainer, pl_module)

    @rank_zero_only
    def on_train_batch_start(self, trainer: "pl.Trainer", pl_module: "pl.LightningModule", batch: Any, batch_idx: int) -> None:
        if self.iter_after_valid:
            mllogger.start(key=mllogger.constants.BLOCK_START,
                        metadata={'first_epoch_num': compute_consumed_mllog_tokens(trainer, pl_module),
                                    'epoch_count': self.tokens_per_block},
                        sync=False)
            self.iter_after_valid = False

    @rank_zero_only
    def load_state_dict(self, state_dict: Dict[str, Any]) -> None:
        print(f":::MLLOG Weight initialization: {state_dict.keys()}")
        return super().load_state_dict(state_dict)

    def on_train_start(self, trainer: "pl.Trainer", pl_module: "pl.LightningModule") -> None:
        if pl_module.cfg.custom.run_warmup_on_synth_data:
            run_training_warmup(trainer, pl_module.cfg.custom.warmup_train_steps)
            if pl_module.cfg.fp8 and pl_module.cfg.custom.reset_fp8_stats_after_warmup:
                reset_fp8_state(pl_module)

        # Note: run on all ranks (to allow synchronization)
        mllogger.log_init_stop_run_start()
        pl_module.setup_data_mmap()

    def maybe_log_run_stop(self, trainer: "pl.Trainer", pl_module: "pl.LightningModule"):
        # Note: run on all ranks (to allow synchronization)
        if self.is_run_stop_already_logged:
            return

        mllogger.end(key=mllogger.constants.RUN_STOP, unique=True, sync=True,
                     metadata=dict(status=self.status))
        mllogger.event(key="trained_samples",
                       value=compute_consumed_mllog_tokens(trainer, pl_module),
                       unique=True, sync=False)
        mllogger.event(key="train_samples",
                       value=compute_consumed_mllog_tokens(trainer, pl_module),
                       unique=True, sync=False)
        self.is_run_stop_already_logged = True


class MetricsLogger(Logger):
    def __init__(self, trainer, model, custom_callback, target_val_log_ppl,
                 extend_run_evals=0,
                 train_loss_key='reduced_train_loss', val_loss_key='val_loss',
                 timing_keys=('train_step_timing', 'train_epoch_timing', 'validation_step_timing', 'validation_epoch_timing'),
                 throughput_key='train_epoch_timing'):
        super().__init__()
        self.trainer = trainer
        self.model = model
        self.custom_callback = custom_callback
        self.target_val_log_ppl = target_val_log_ppl
        self.val_loss_key = val_loss_key
        self.train_loss_key = train_loss_key
        self.timing_keys = timing_keys
        self.throughput_key = throughput_key

        self.extend_run_evals = extend_run_evals
        self.extension_eval_idx = 0
        self.is_target_reached = False


    def log_metrics(self, metrics: Dict[str, float],
                    step: Optional[int] = None) -> None:
        if self.val_loss_key in metrics:
            self._log_val_metrics(metrics, step)
        self._log_throughputs(metrics, step)
        # Consumed samples is shifted by 1 (in terms of gbs), beacuse `trainer.global_step`
        # is not incremented by the time `consumed_samples` is logged (in model forward)
        # Recomputing in here:
        if 'consumed_samples' in self.trainer.callback_metrics:
            correct_consumed_samples = self.model.compute_consumed_samples(self.trainer.global_step - self.model.init_global_step)
            self.trainer.callback_metrics['consumed_samples'].fill_(correct_consumed_samples)


    def _log_val_metrics(self, metrics: Dict[str, float],
                         step: Optional[int] = None):
        assert self.val_loss_key in metrics, metrics.keys()
        val_loss = metrics[self.val_loss_key]
        val_ppl = math.exp(min(20, val_loss))
        mllogger.event(mllogger.constants.EVAL_ACCURACY, value=val_loss,
                       metadata=dict(epoch_num=compute_consumed_mllog_tokens(self.trainer, self.model)))

        if not self.is_target_reached and val_loss <= self.target_val_log_ppl:
            logger.info(f'Target Log PPL {self.target_val_log_ppl} reached')
            self.custom_callback.set_success_status()
            self.is_target_reached = True
            if self.extend_run_evals:
                logger.info(f'Continuing training for {self.extend_run_evals} extra eval intervals')
            else:
                logger.info(f'Stopping training after reaching target log PPL')
                self.trainer.should_stop = True

        if self.is_target_reached and self.extend_run_evals:
            if self.extension_eval_idx >= self.extend_run_evals:
                logger.info(f'Stopping training after {self.extend_run_evals} extra eval intervals')
                self.trainer.should_stop = True
            self.extension_eval_idx += 1

    def _log_throughputs(self, metrics: Dict[str, float],
                         step: Optional[int] = None):

        for timing_key in self.timing_keys:
            if timing_key in metrics:
                timing = metrics[timing_key]
                samples = compute_consumed_mllog_tokens(self.trainer, self.model)
                loss_data = {}
                if self.train_loss_key in metrics:
                    loss_data[self.train_loss_key] = metrics[self.train_loss_key]
                if os.environ.get("USE_DATETIME", "0") == "1":
                    mllogger.event(key='tracked_stats', metadata={'step': samples},
                        value={timing_key: timing, **loss_data, 'time_now': str(datetime.now())})
                else:
                    mllogger.event(key='tracked_stats', metadata={'step': samples},
                        value={timing_key: timing, **loss_data})

        if self.throughput_key in metrics:
            timing = metrics[self.throughput_key]
            samples = compute_consumed_mllog_tokens(self.trainer, self.model)
            throughput = samples / timing
            mllogger.event(key='tracked_stats', metadata={'step': samples},
                           value={'throughput': throughput})

    @rank_zero_only
    def log_hyperparams(self, params: Union[Dict[str, Any], Namespace],
                        *args: Any, **kwargs: Any) -> None:
        model_cfg = params.cfg
        mllogger.mlperf_submission_log('gpt3')

        mllogger.event(key=mllogger.constants.SEED, value=model_cfg.seed,
                       sync=False, unique=True)
        mllogger.event(key=mllogger.constants.GLOBAL_BATCH_SIZE,
                       value=model_cfg.global_batch_size, sync=False)
        b1, b2 = model_cfg.optim.betas
        mllogger.event(key="opt_name", value="adam", sync=False, unique=True)
        mllogger.event(key=mllogger.constants.OPT_BASE_LR,
                       value=model_cfg.optim.lr, sync=False, unique=True)
        mllogger.event(key="opt_end_learning_rate",
                       value=model_cfg.optim.sched.min_lr, sync=False, unique=True)
        mllogger.event(key="opt_adam_beta_1", value=b1, sync=False, unique=True)
        mllogger.event(key="opt_adam_beta_2", value=b2, sync=False, unique=True)
        mllogger.event(key="opt_adam_epsilon",
                       value=self.model.optimizers().optimizer.param_groups[0]['eps'], sync=False, unique=True)
        mllogger.event(key="opt_weight_decay",
                       value=model_cfg.optim.weight_decay, sync=False, unique=True)
        mllogger.event(key="opt_learning_rate_decay_steps",
                       value=int(model_cfg.optim.sched.max_steps_for_lr_sched), sync=False, unique=True)
        mllogger.event(key="opt_learning_rate_warmup_steps",
                       value=int(model_cfg.optim.sched.warmup_steps), sync=False, unique=True)
        mllogger.event(key="opt_learning_rate_decay_schedule",
                       value="cosine with linear warmup", sync=False, unique=True)
        mllogger.event(key="opt_gradient_clip_norm",
                       value=self.trainer.gradient_clip_val, sync=False, unique=True)
        mllogger.event(key="init_checkpoint_step",
                       value=model_cfg.custom.init_global_step, sync=False, unique=True)
        mllogger.event(key=mllogger.constants.GRADIENT_ACCUMULATION_STEPS,
                       value=get_num_microbatches(), sync=False, unique=True)
        mllogger.event(key="max_sequence_length",
                       value=model_cfg.encoder_seq_length, sync=False, unique=True)
        mllogger.event(key=mllogger.constants.EVAL_SAMPLES,
                       value=11590004, sync=False, unique=True)

    @property
    def name(self) -> Optional[str]:
        return 'mlperf-metrics'

    @property
    def version(self) -> Optional[Union[int, str]]:
        return 1


class DistributedCheckpointIO(TorchCheckpointIO):
    def __init__(self, load_directly_on_device, use_two_stage_loading: bool, cpu_transfer: bool) -> None:
        super().__init__()
        self.load_directly_on_device = load_directly_on_device
        self.use_two_stage_loading = use_two_stage_loading
        self.cpu_transfer = cpu_transfer

    def save_dist_checkpoint(self, checkpoint: Dict[str, Any], path: _PATH,
                        lightning_module: pl.LightningModule,
                        storage_options: Optional[Any] = None) -> None:
        start = time.time()
        checkpoint = generate_unified_state_dict(checkpoint, lightning_module)
        if torch.distributed.get_rank() == 0:
            os.makedirs(path, exist_ok=True)
        torch.distributed.barrier()
        logger.info(f'Time spent in init_save_checkpoint: {time.time() - start}s')
        dist_checkpointing.save(checkpoint, path)
        torch.distributed.barrier()
        logger.info(f'Time spent in save_checkpoint: {time.time() - start}s')

    def load_dist_checkpoint(self, path: _PATH, lightning_module: pl.LightningModule) -> Dict[str, Any]:
        start = time.time()
        state_dict = generate_unified_state_dict(None, lightning_module)
        if self.use_two_stage_loading:
            load_strategy = TwoStageDataParallelLoadShardedStrategy(parallel_state.get_data_parallel_group(),
                                                                    self.cpu_transfer)
        elif self.load_directly_on_device:
            load_strategy = TensorStoreLoadShardedStrategy(self.load_directly_on_device)
        else:
            load_strategy = None  # use default strategy
        state_dict = dist_checkpointing.load(state_dict, path, load_strategy)
        state_dict['state_dict'] = {}
        state_dict = self._fix_tensors_device(state_dict)
        torch.distributed.barrier()
        logger.info(f'Time spent in load_checkpoint: {time.time() - start}s')
        return state_dict

    def _fix_tensors_device(self, ckpt: Dict) -> Dict:
        assert torch.cuda.is_initialized(), (torch.cuda.is_available(), torch.cuda.is_initialized())
        cur_dev = torch.device("cuda", index=torch.cuda.current_device())

        def _fix_device(t):
            if isinstance(t, torch.Tensor) and t.is_cuda and t.device != cur_dev:
                t = t.to(cur_dev)
            return t
        return dict_list_map_outplace(_fix_device, ckpt)

    def remove_dist_checkpoint(self, path: _PATH) -> None:
        start = time.time()
        fs = get_filesystem(path)
        if fs.exists(path):
            fs.rm(path, recursive=True)
            logger.debug(f"Removed checkpoint: {path}")
        logger.info(f'Time spent in remove_checkpoint: {time.time() - start}s')


class EpochTimingCallback(TimingCallback):
    def __init__(self, timer: NamedTimer):
        # NOTE: don't call super().__init__() to reuse timer
        self.timer = timer

    def _on_epoch_start(self, name):
        self._on_batch_start(name)

    def _on_epoch_end(self, name, pl_module):
        self.timer.stop(name)
        # Set the `batch_size=1` as WAR for `dataloader_iter`, which is not used for any metric
        pl_module.log(name, self.timer[name], on_step=False, on_epoch=True, batch_size=1)

    def on_validation_epoch_start(self, trainer, pl_module):
        self._on_batch_start("validation_epoch_timing")

    def on_validation_epoch_end(self, trainer, pl_module):
        self._on_epoch_end("validation_epoch_timing", pl_module)

    def on_train_epoch_start(self, trainer, pl_module):
        self._on_batch_start("train_epoch_timing")

    def on_train_epoch_end(self, trainer, pl_module):
        self._on_epoch_end("train_epoch_timing", pl_module)


class CustomNLPDDPStrategy(NLPDDPStrategy):
    """ Allows distributed checkpoint format. """

    def __init__(self, use_dist_ckpt, *args, **kwargs):
        super(CustomNLPDDPStrategy, self).__init__(*args, **kwargs)
        self.use_dist_ckpt = use_dist_ckpt

    def save_checkpoint(self, checkpoint: Dict[str, Any], filepath: _PATH,
                        storage_options: Optional[Any] = None) -> None:
        if self.use_dist_ckpt:
            self.checkpoint_io.save_dist_checkpoint(checkpoint, filepath, self.lightning_module)
        else:
            super().save_checkpoint(checkpoint, filepath, storage_options)

    def load_checkpoint(self, checkpoint_path: _PATH) -> Dict[str, Any]:
        if dist_checkpointing.check_is_distributed_checkpoint(checkpoint_path):
            torch.cuda.empty_cache()
            ckpt = self.checkpoint_io.load_dist_checkpoint(checkpoint_path, self.lightning_module)
        else:
            ckpt = super().load_checkpoint(checkpoint_path)
        if 'pytorch-lightning_version' in ckpt:
            logger.info(f'Detected resuming from a PTL checkpoint step {ckpt["global_step"]}.'
                         f' Resetting loop counters.')
            ckpt = self.reset_steps_and_loops(ckpt)
        else:
            logger.info('Detected resuming from reference checkpoint.')
            ckpt = self.inject_gbs_dependent_values(ckpt)
            ckpt = self.inject_ptl_version(ckpt)

        # Setting ckpt['global_step'] is not enough in PTL > 1.7
        self.lightning_module.trainer.fit_loop.epoch_loop.batch_loop.optimizer_loop.optim_progress.optimizer.step.total.completed = ckpt['global_step']
        return ckpt

    def reset_steps_and_loops(self, ckpt):
        keys_to_remove = ['loops', 'callbacks', 'hparams_name', 'hyper_parameters']
        for key in keys_to_remove:
            del ckpt[key]
        return ckpt

    def inject_ptl_version(self, ckpt):
        ckpt['pytorch-lightning_version'] = '1.7'
        return ckpt

    def inject_gbs_dependent_values(self, ckpt):
        """ This is very MLPerf specific (resuming from the same checkpoint for different hparams). """
        step = self.lightning_module.cfg.custom.init_global_step + 1
        lr_scheduler = self.lightning_module.lr_schedulers()
        initial_lr = lr_scheduler.base_lrs[0]
        last_lr = lr_scheduler._get_linear_warmup_with_cosine_annealing_lr(step)
        logger.info(f'Injecting the following hparams: {step=}, {last_lr=}, {initial_lr=}')

        # Global
        ckpt['global_step'] = step

        # LR scheduler
        assert len(ckpt['lr_schedulers']) == 1, len(ckpt['lr_schedulers'])
        ckpt['lr_schedulers'] = [{
            '_last_lr': last_lr,
            'last_epoch': step,
            '_step_count': step,
        }]
        # All the other fields will be untouched (which is good)
        # including: 'max_steps', 'warmup_steps', 'constant_steps', 'decay_steps', 'min_lr', 'base_lrs'

        # Optimizer
        assert len(ckpt['optimizer_states']) == 1, len(ckpt['optimizer_states'])
        assert len(ckpt['optimizer_states'][0]['optimizer']['param_groups']) == 1, len(ckpt['optimizer_states'][0]['optimizer']['param_groups'])
        optim_meta = ckpt['optimizer_states'][0]['optimizer']['param_groups'][0]
        optim_meta.update({
            'step': step,
            'initial_lr': initial_lr,
            'lr': last_lr[0],
        })
        return ckpt

    def restore_checkpoint_after_setup(self):
        return True

    def remove_checkpoint(self, filepath: _PATH) -> None:
        """ Revert to default PTL behavior. """
        if dist_checkpointing.check_is_distributed_checkpoint(filepath):
            if self.is_global_zero:
                self.checkpoint_io.remove_dist_checkpoint(filepath)
        else:
            super().remove_checkpoint(filepath)

    def load_model_state_dict(self, checkpoint) -> None:
        model = self.lightning_module.model
        if isinstance(model, list):
            # distributed ckpt with interleaved and regular checkpoint with interleaved
            for i in range(len(model)):
                parallel_state.set_virtual_pipeline_model_parallel_rank(i)
                model[i].module.load_state_dict(checkpoint[f'model{i}'], strict=True)
            parallel_state.set_virtual_pipeline_model_parallel_rank(0)

        if checkpoint['state_dict']:
            # regular checkpoint with or without interleaved
            super().load_model_state_dict(checkpoint)
        elif not isinstance(model, list):
            # distributed checkpoint without interleaved pipeline
            model.module.load_state_dict(checkpoint[f'model0'], strict=True)

    def synthetic_training_step(self):
        return self.training_step(*self.lightning_module.get_synthetic_input())


class CustomMegatronGPTModel(MegatronGPTModel):
    def on_load_checkpoint(self, checkpoint) -> None:
        """ Super class implementation moved to CustomNLPDDPStrategy.load_model_state_dict
        """
        pass

    def setup_data_mmap(self):
        if self.cfg.data.get('delay_data_mmap', False) and not isinstance(self._train_ds, MockGPTDataset):
            if self._train_ds:
                self._train_ds.create_data_mmap()
            if self._validation_ds:
                self._validation_ds.create_data_mmap()
            if self._test_ds:
                self._test_ds.create_data_mmap()

    def get_synthetic_input(self):
        if isinstance(self._train_ds, MockGPTDataset):
            single_data = self._train_ds[0]
        else:
            text = torch.ones(self.cfg.data.seq_length + 1, dtype=torch.int32) * 3545  # some token
            text[-1] = 0

            tokens = text[:-1].contiguous()
            labels = text[1:].contiguous()

            train_ds = self._train_ds.datasets[0]
            attention_mask, loss_mask, position_ids = _create_ltor_masks_and_position_ids(
                tokens, train_ds.eos_id, train_ds.reset_position_ids,
                train_ds.reset_attention_mask, train_ds.eod_mask_loss,
            )

            single_data = {
                'tokens': tokens,
                'labels': labels,
                'attention_mask': attention_mask,
                'loss_mask': loss_mask,
                'position_ids': position_ids,
            }
        if isinstance(self._train_dl.batch_sampler, BaseMegatronBatchSampler):
            batch = default_collate([single_data] * self.cfg.micro_batch_size * get_num_microbatches())
            args = [batch, 0]
        elif isinstance(self._train_dl.batch_sampler, MegatronPretrainingSampler):
            batch = default_collate([single_data] * self.cfg.micro_batch_size)
            args = [repeat(batch), 0]
        else:
            raise NotImplementedError(f'No synthetic data implementation for data sampler "{self._train_dl.batch_sampler}"')
        return args

    def _register_sharded_tensor_state_dict_hooks_if_available(self) -> None:
        logger.info('Overriding _register_sharded_tensor_state_dict_hooks_if_available'
                     ' to mitigate incompatibility of PTL and PyTorch')
        return

    def _extract_consumed_samples_from_ckpt(self, ckpt_path):
        consumed_samples = super()._extract_consumed_samples_from_ckpt(ckpt_path)
        if consumed_samples == 0 and self.cfg.custom.override_zero_consumed_samples:
            consumed_samples = self.cfg.custom.init_global_step * self.cfg.global_batch_size
            logger.info(f'Overriding consumed_samples from 0 to {consumed_samples}')
        return consumed_samples


def configure_pre_validation_training_loop(trainer: pytorch_lightning.Trainer) -> None:
    if type(trainer.fit_loop.epoch_loop) != TrainingEpochLoop and not isinstance(trainer.fit_loop.epoch_loop, SkipResumeTrainingValidationLoop):
        return
    loop = PreValidationTrainingValidationLoop(trainer.min_steps, trainer.max_steps)
    loop.trainer = trainer
    trainer.fit_loop.epoch_loop = loop


class PreValidationTrainingValidationLoop(TrainingEpochLoop):
    """
    Extend the PTL Epoch loop to run validating on start.
    """

    def __init__(self, min_steps: Optional[int] = None, max_steps: int = -1) -> None:
        super().__init__(min_steps, max_steps)
        self.restarting = True

    def _should_check_val_fx(self) -> bool:
        if self.restarting and self.global_step == 0:
            return True
        return super()._should_check_val_fx()


def setup_auxiliary_loggers(log_marker='AUX'):
    """ Sets up non-NeMo loggers. Must be called after NeMo logging is set up.

    - Adds formatting to all logs
    - Removes INFO handlers on non-zero-ranks
    """
    class CustomFormatter(BaseNeMoFormatter):
        DEFAULT_FORMAT = BaseNeMoFormatter.DEFAULT_FORMAT.replace('NeMo', log_marker)

    class CustomDebugFormatter(DebugNeMoFormatter):
        DEFAULT_FORMAT = DebugNeMoFormatter.DEFAULT_FORMAT.replace('NeMo', log_marker)

    root = logging.getLogger()
    if not root.handlers:
        logger.warning(f'Failed to setup auxiliary loggers. Empty root logger handlers')
        return

    root_handler = root.handlers[0]
    if not isinstance(root_handler, logging.StreamHandler):
        logger.warning(f'Failed to setup auxiliary loggers. Unexpected root logger handler: {root.handlers[0]}')
        return

    if get_envbool(NEMO_ENV_VARNAME_TESTING, False):
        root_handler.setFormatter(CustomDebugFormatter())
        root.setLevel(logging.DEBUG)
    elif is_global_rank_zero():
        root_handler.setFormatter(CustomFormatter())
    else:
        # removing INFO handlers for non-zero ranks
        root.handlers.clear()
