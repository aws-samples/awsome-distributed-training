import functools

from transformers.models.llama.modeling_llama import LlamaDecoderLayer
from transformers.models.mamba.modeling_mamba import MambaBlock

from torch.distributed.fsdp.wrap import transformer_auto_wrap_policy


def get_wrapper(model_name):
    if "llama2" in model_name:

        auto_wrap_policy = functools.partial(
            transformer_auto_wrap_policy,
            transformer_layer_cls={
                LlamaDecoderLayer,
            },
        )
    elif "mamba" in model_name:
        auto_wrap_policy = functools.partial(
            transformer_auto_wrap_policy,
            transformer_layer_cls={
                MambaBlock
        },
    )
    else:
        raise ValueError(f"Model {model_name} currently not supported.")

    return auto_wrap_policy