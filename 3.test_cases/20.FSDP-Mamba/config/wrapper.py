import functools

from mamba_ssm.modules.mamba_simple import Block

from torch.distributed.fsdp.wrap import transformer_auto_wrap_policy

from torch.distributed.algorithms._checkpoint.checkpoint_wrapper import (
   checkpoint_wrapper,
   CheckpointImpl,
   apply_activation_checkpointing,
)

def get_wrapper(model_name):
    auto_wrap_policy = functools.partial(
        transformer_auto_wrap_policy,
        transformer_layer_cls={
            Block
            },
    )
    return auto_wrap_policy

def get_checkpointing_wrapper(model_name):

    non_reentrant_wrapper = functools.partial(
        checkpoint_wrapper,
        offload_to_cpu=False,
        checkpoint_impl=CheckpointImpl.NO_REENTRANT,
    )

    check_fn = lambda submodule: isinstance(submodule, Block)

    return check_fn

