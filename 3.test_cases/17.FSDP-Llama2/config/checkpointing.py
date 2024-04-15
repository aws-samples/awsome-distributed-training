from functools import partial

from transformers.models.llama.modeling_llama import LlamaDecoderLayer
from transformers.models.mamba.modeling_mamba import MambaBlock
from torch.distributed.algorithms._checkpoint.checkpoint_wrapper import (
    CheckpointImpl,
    apply_activation_checkpointing,
    checkpoint_wrapper,
)


no_reentrant_wrapper = partial(
    checkpoint_wrapper,
    checkpoint_impl=CheckpointImpl.NO_REENTRANT,
)


def apply_fsdp_checkpointing(model, every_xth_item):
    def selective_checkpointing(submodule):
        selective_checkpointing.__dict__.setdefault("_count", 0)

        if isinstance(submodule, LlamaDecoderLayer) or isinstance(submodule, MambaBlock):
            selective_checkpointing._count += 1
            if (
                not every_xth_item
                or selective_checkpointing._count % every_xth_item == 0
            ):
                return True
        return False


    apply_activation_checkpointing(
        model,
        checkpoint_wrapper_fn=no_reentrant_wrapper,
        check_fn=selective_checkpointing,
    )