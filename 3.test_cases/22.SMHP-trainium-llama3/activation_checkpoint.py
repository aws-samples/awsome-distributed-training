from typing import Any, Dict, Iterator, Tuple
import torch.nn as nn

import torch
from torch_xla.utils.checkpoint import checkpoint as torch_checkpoint
from neuronx_distributed.parallel_layers.parallel_state import rmsg
from neuronx_distributed.utils.logger import get_logger
from torch.distributed.utils import _replace_by_prefix

logger = get_logger()

_CHECKPOINT_WRAPPED_MODULE = "mod"
_CHECKPOINT_PREFIX = _CHECKPOINT_WRAPPED_MODULE + "."

class CheckPointWrapper(torch.nn.Module):
    def __init__(self, mod) -> None:
        super().__init__()
        self.mod = mod
        # state_dict post hook to remove prefix to allow loading into a
        # non-checkpoint wrapped module.
        self._register_state_dict_hook(self._post_state_dict_hook)
        # load_state_dict pre-hook to allow loading back into
        # checkpoint-wrapped module.
        self._register_load_state_dict_pre_hook(
            self._pre_load_state_dict_hook, with_module=True
        )


    def forward(self, *args, **kwargs):
        ordered_args = list(args)
        for value in kwargs.values():
            ordered_args += [value]

        # Note: checkpoint cannot accept kwargs
        return torch_checkpoint(self.mod, *ordered_args, use_reentrant=True)
    
    def named_parameters(
        self,
        *args,
        **kwargs,
    ) -> Iterator[Tuple[str, torch.nn.Parameter]]:
        """
        Overrides :meth:`named_parameters()` to intercept parameter names and
        remove all occurrences of ``_CHECKPOINT_PREFIX``.
        """
        for param_name, param in super().named_parameters(*args, **kwargs):
            updated_name = param_name.replace(_CHECKPOINT_PREFIX, "")
            yield updated_name, param
    
    def named_modules(self,*args,**kwargs):
        for module_name, module in super().named_modules(*args, **kwargs):
            updated_name = module_name.replace(_CHECKPOINT_PREFIX, "")
            yield updated_name, module

    @staticmethod
    def _post_state_dict_hook(
        module: nn.Module,
        state_dict: Dict[str, Any],
        prefix: str,
        *args: Any,
    ) -> Dict[str, Any]:
        """
        _post_state_dict_hook() is called after the state_dict() of this
        FSDP module is executed. For ``checkpoint_wrapper``, it will strip
        checkpoint-wrapped module prefix so that this module can be loaded into
        non-checkpointed modules. It would still be able to be loaded into
        checkpoint-wrapped modules as this class adds the prefix back before
        loading the state_dict.
        """
        _replace_by_prefix(state_dict, f"{prefix}{_CHECKPOINT_PREFIX}", prefix)
        return state_dict
    
    @staticmethod
    def _pre_load_state_dict_hook(
        module: nn.Module,
        state_dict: Dict[str, Any],
        prefix: str,
        *args: Any,
    ) -> None:
        """
        ``_pre_state_dict_hook` is called before ``self._load_from_state_dict()``
        is called. For ``checkpoint_wrapper``, it will add back the module
        prefix so that non-checkpointed modules can be loaded into
        checkpoint_wrapper modules properly.
        """
        _replace_by_prefix(state_dict, prefix, prefix + f"{_CHECKPOINT_PREFIX}")

    

def apply_checkpoint(dist_model, layers_to_checkpoint=None):
    checkpoint_wrapper_added = False
    if layers_to_checkpoint is not None and len(layers_to_checkpoint) == 0:
        raise RuntimeError(
            rmsg(f"invalid input layers_to_checkpoint {layers_to_checkpoint}, can't be empty")
        )
    for name, module in dist_model.local_module.named_children():
        # checkpoint layers that are provided in input
        # if layers not provide in input, then checkpoint if it is transformer layer
        if (layers_to_checkpoint and name in layers_to_checkpoint) or (
            not layers_to_checkpoint and type(module) == dist_model.transformer_layer_cls
        ):
            # add_module replaces old module with our own custom module.
            # https://pytorch.org/docs/stable/_modules/torch/nn/modules/module.html#Module.add_module
            dist_model.local_module.add_module(name, CheckPointWrapper(module))
            checkpoint_wrapper_added = True
    if layers_to_checkpoint is not None and not checkpoint_wrapper_added:
        logger.warning(
            rmsg(f"layers_to_checkpoint {layers_to_checkpoint} do not exist in the graph")
        )
    elif layers_to_checkpoint is None and not checkpoint_wrapper_added:
        logger.warning(
            rmsg(
                f"During applying activation checkpointing, transformer_layer_cls {dist_model.transformer_layer_cls.__name__} can not be found in stage {dist_model.pipeline_parallel_rank}, skipping..."
            )
        )