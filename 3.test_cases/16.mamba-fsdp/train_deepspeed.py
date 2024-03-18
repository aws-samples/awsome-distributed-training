from transformers import (
    default_data_collator,
    TrainingArguments,
    Trainer,
    HfArgumentParser,
    set_seed,
    get_scheduler,
    SchedulerType
)
import deepspeed

import argparse
from dataclasses import dataclass, field
from typing import Optional
from datasets import load_dataset, load_from_disk

from transformers.trainer_utils import get_last_checkpoint
import numpy as np
import os
import shutil

import math
from functools import partial

from collections import namedtuple

import torch
import torch.nn as nn
from torch.nn import CrossEntropyLoss
from transformers import PretrainedConfig, PreTrainedModel
import torch.distributed as dist

from mamba_ssm.modules.mamba_simple import Mamba, Block
from mamba_ssm.utils.generation import GenerationMixin
from mamba_ssm.utils.hf import load_config_hf, load_state_dict_hf

try:
    from mamba_ssm.ops.triton.layernorm import RMSNorm, layer_norm_fn, rms_norm_fn
except ImportError:
    RMSNorm, layer_norm_fn, rms_norm_fn = None, None, None


backend = "nccl"

@dataclass
class TrainingArgs:
    
    """
    Arguments required to set up trainer.
    """

    world_size: int = field(
        default=24,
        metadata={
            "help": (
                "number of GPUs being used for training."
            )
        },
    )
    epochs: Optional[int] = field(
        default=3,
        metadata={
            "help": "Number of epochs to train for. "},
    )
    max_steps: Optional[int] = field(
        default=None, metadata={
            "help": "Number of epochs to train for. "},
    )
    batch_size: Optional[int] = field(
        default=1, metadata={
            "help": "Batch size to use for training."},
    )
    lr: Optional[float] = field(
        default=1e-4, metadata={
            "help": "Learning rate to use for training."},
    )
    optimizer: Optional[str] = field(
        default="adam_hf", metadata={
            "help": "Optimizer to use for training."},
    )
    seed: Optional[int]= field(
        default=42, metadata={
            "help": "Seed to use for training."},
    )
    num_train_epochs: Optional[int] = field(
        default=3, metadata={
            "help": "Total number of training epochs to perform."},
    )
    gradient_checkpointing: Optional[bool] = field(
        default=True, metadata={
            "help": "Whether to use gradient checkpointing to save memory."},
    )
    bf16: Optional[bool] = field(
        default=True if torch.cuda.get_device_capability()[0] == 8 else False, metadata={
            "help": "Whether to use bf16."},
    )
    learning_date: Optional[float] = field(
        default=1e-4, metadata={
            "help": "Initial learning rate (after the potential warmup period) to use."},
    )

    max_train_steps: Optional[int] = field(
        default=None, metadata={
            "help": "Total number of training steps to perform. If provided, overrides num_train_epochs."},
    )
    gradient_accumulation_steps: Optional[int] = field(
        default=3, metadata={
            "help": "Number of updates steps to accumulate before performing a backward/update pass."},
    )
    lr_scheduler_type: Optional[str]= field(
        default="linear", metadata={
            "help": "The scheduler type to use. From linear, cosine, cosine_with_restarts, polynomial, constant, constant_with_warmup"},
    )
    num_warmup_steps: Optional[int] = field(
        default=0, metadata={
            "help": "Number of steps for the warmup in the lr scheduler."},
    )
    deepspeed_config: Optional[str] = field(
        default=None, metadata={
            "help": "Path to Deepspeed config file."},
    )
    weight_decay: Optional[float] = field(
        default=1e-1, metadata={
            "help": "Weight decay to use."},
    )    
    learning_rate: float = field(
        default=1e-4, metadata={
            "help": "Initial learning rate (after the potential warmup period) to use."},
    )
  
 
@dataclass
class ModelArguments:
    """
    Arguments pertaining to which model/config/tokenizer we are going to fine-tune, or train from scratch.
    """

    model_name_or_path: Optional[str] = field(
        default=None,
        metadata={
            "help": (
                "The model checkpoint for weights initialization. Don't set if you want to train a model from scratch."
            )
        },
    )
    model_type: Optional[str] = field(
        default=None,
        metadata={
            "help": "If training from scratch, pass a model type from the list: "},
    )
    config_overrides: Optional[str] = field(
        default=None, metadata={
            "help": (
                "Override some existing default config settings when a model is trained from scratch. Example: "
                "n_embd=10,resid_pdrop=0.2,scale_attn_weights=false,summary_type=cls_index")}, )
    config_name: Optional[str] = field(
        default=None, metadata={
            "help": "Pretrained config name or path if not the same as model_name"})
    tokenizer_name: Optional[str] = field(
        default=None, metadata={
            "help": "Pretrained tokenizer name or path if not the same as model_name"})
    cache_dir: Optional[str] = field(
        default=None, metadata={
            "help": "Where do you want to store the pretrained models downloaded from huggingface.co"}, )
    use_fast_tokenizer: bool = field(
        default=True, metadata={
            "help": "Whether to use one of the fast tokenizer (backed by the tokenizers library) or not."}, )
    model_revision: str = field(
        default="main", metadata={
            "help": "The specific model version to use (can be a branch name, tag name or commit id)."}, )
    token: str = field(
        default=None,
        metadata={
            "help": (
                "The token to use as HTTP bearer authorization for remote files. If not specified, will use the token "
                "generated when running `huggingface-cli login` (stored in `~/.huggingface`)."
            )
        },
    )
    use_auth_token: bool = field(
        default=None,
        metadata={
            "help": "The `use_auth_token` argument is deprecated and will be removed in v4.34. Please use `token` instead."
        },
    )
    trust_remote_code: bool = field(
        default=False, metadata={
            "help": (
                "Whether or not to allow for custom models defined on the Hub in their own modeling files. This option"
                "should only be set to `True` for repositories you trust and in which you have read the code, as it will "
                "execute code present on the Hub on your local machine.")}, )
    torch_dtype: Optional[str] = field(
        default=None,
        metadata={
            "help": (
                "Override the default `torch.dtype` and load the model under this dtype. If `auto` is passed, the "
                "dtype will be automatically derived from the model's weights."),
            "choices": [
                "auto",
                "bfloat16",
                "float16",
                "float32"],
        },
    )
    low_cpu_mem_usage: bool = field(
        default=False,
        metadata={
            "help": (
                "It is an option to create the model as an empty shell, then only materialize its parameters when the pretrained weights are loaded. "
                "set True will benefit LLM loading time and RAM consumption."
            )
        },
    )
    num_workers: int = field(
        default=4,
        metadata={"help": "number of workers"},
    )

    def __post_init__(self):
        if self.config_overrides is not None and (
                self.config_name is not None or self.model_name_or_path is not None):
            raise ValueError(
                "--config_overrides can't be used in combination with --config_name or --model_name_or_path"
            )


@dataclass
class DataTrainingArguments:
    """
    Arguments pertaining to what data we are going to input our model for training and eval.
    """

    dataset_name: Optional[str] = field(
        default=None, metadata={
            "help": "The name of the dataset to use (via the datasets library)."})
    dataset_config_name: Optional[str] = field(
        default=None, metadata={
            "help": "The configuration name of the dataset to use (via the datasets library)."})
    train_file: Optional[str] = field(
        default=None, metadata={
            "help": "The input training data file (a text file)."})
    validation_file: Optional[str] = field(
        default=None, metadata={
            "help": "An optional input evaluation data file to evaluate the perplexity on (a text file)."}, )
    share_directory: str = field(
        default='/home/ubuntu/share',
        metadata={"help": "share storage directory"},
    )
    max_train_samples: Optional[int] = field(
        default=None, metadata={
            "help": (
                "For debugging purposes or quicker training, truncate the number of training examples to this "
                "value if set.")}, )
    max_eval_samples: Optional[int] = field(
        default=None, metadata={
            "help": (
                "For debugging purposes or quicker training, truncate the number of evaluation examples to this "
                "value if set.")}, )
    streaming: bool = field(default=False, metadata={"help": "Enable streaming mode"})
    block_size: Optional[int] = field(
        default=None,
        metadata={
            "help": (
                "Optional input sequence length after tokenization. "
                "The training dataset will be truncated in block of this size for training. "
                "Default to the model max input length for single sentence inputs (take into account special tokens)."
            )
        },
    )
    overwrite_cache: bool = field(
        default=False, metadata={"help": "Overwrite the cached training and evaluation sets"}
    )
    validation_split_percentage: Optional[int] = field(
        default=5,
        metadata={
            "help": "The percentage of the train set used as validation set in case there's no validation split"
        },
    )
    preprocessing_num_workers: Optional[int] = field(
        default=None,
        metadata={"help": "The number of processes to use for the preprocessing."},
    )
    keep_linebreaks: bool = field(
        default=True, metadata={"help": "Whether to keep line breaks when using TXT files or not."}
    )
    checkpoint_steps: int = field(
        default=50,
        metadata={"help": "number of workers"},
    )


class MambaConfig(PretrainedConfig):
    model_type = 'mamba'


def create_block(
    d_model,
    ssm_cfg=None,
    norm_epsilon=1e-5,
    rms_norm=False,
    residual_in_fp32=False,
    fused_add_norm=False,
    layer_idx=None,
    device=None,
    dtype=None,
):
    if ssm_cfg is None:
        ssm_cfg = {}
    factory_kwargs = {"device": device, "dtype": dtype}
    mixer_cls = partial(Mamba, layer_idx=layer_idx, **ssm_cfg, **factory_kwargs)
    norm_cls = partial(
        nn.LayerNorm if not rms_norm else RMSNorm, eps=norm_epsilon, **factory_kwargs
    )
    block = Block(
        d_model,
        mixer_cls,
        norm_cls=norm_cls,
        fused_add_norm=fused_add_norm,
        residual_in_fp32=residual_in_fp32,
    )
    block.layer_idx = layer_idx
    return block


def _init_weights(
    module,
    n_layer,
    initializer_range=0.02,  # Now only used for embedding layer.
    rescale_prenorm_residual=True,
    n_residuals_per_layer=1,  # Change to 2 if we have MLP
):
    if isinstance(module, nn.Linear):
        if module.bias is not None:
            if not getattr(module.bias, "_no_reinit", False):
                nn.init.zeros_(module.bias)
    elif isinstance(module, nn.Embedding):
        nn.init.normal_(module.weight, std=initializer_range)

    if rescale_prenorm_residual:
        # Reinitialize selected weights subject to the OpenAI GPT-2 Paper Scheme:
        #   > A modified initialization which accounts for the accumulation on the residual path with model depth. Scale
        #   > the weights of residual layers at initialization by a factor of 1/√N where N is the # of residual layers.
        #   >   -- GPT-2 :: https://openai.com/blog/better-language-models/
        #
        # Reference (Megatron-LM):
        # https://github.com/NVIDIA/Megatron-LM/blob/main/megatron/model/gpt_model.py
        for name, p in module.named_parameters():
            if name in ["out_proj.weight", "fc2.weight"]:
                # Special Scaled Initialization --> There are 2 Layer Norms per Transformer Block
                # Following Pytorch init, except scale by 1/sqrt(2 * n_layer)
                # We need to reinit p since this code could be called multiple times
                # Having just p *= scale would repeatedly scale it down
                nn.init.kaiming_uniform_(p, a=math.sqrt(5))
                with torch.no_grad():
                    p /= math.sqrt(n_residuals_per_layer * n_layer)


class MixerModel(nn.Module):
    def __init__(
        self,
        d_model: int,
        n_layer: int,
        vocab_size: int,
        ssm_cfg=None,
        norm_epsilon: float = 1e-5,
        rms_norm: bool = False,
        initializer_cfg=None,
        fused_add_norm=False,
        residual_in_fp32=False,
        device=None,
        dtype=None,
    ) -> None:
        factory_kwargs = {"device": device, "dtype": dtype}
        super().__init__()
        self.residual_in_fp32 = residual_in_fp32

        self.embedding = nn.Embedding(vocab_size, d_model, **factory_kwargs)

        # We change the order of residual and layer norm:
        # Instead of LN -> Attn / MLP -> Add, we do:
        # Add -> LN -> Attn / MLP / Mixer, returning both the residual branch (output of Add) and
        # the main branch (output of MLP / Mixer). The model definition is unchanged.
        # This is for performance reason: we can fuse add + layer_norm.
        self.fused_add_norm = fused_add_norm
        if self.fused_add_norm:
            if layer_norm_fn is None or rms_norm_fn is None:
                raise ImportError("Failed to import Triton LayerNorm / RMSNorm kernels")

        self.layers = nn.ModuleList(
            [
                create_block(
                    d_model,
                    ssm_cfg=ssm_cfg,
                    norm_epsilon=norm_epsilon,
                    rms_norm=rms_norm,
                    residual_in_fp32=residual_in_fp32,
                    fused_add_norm=fused_add_norm,
                    layer_idx=i,
                    **factory_kwargs,
                )
                for i in range(n_layer)
            ]
        )

        self.norm_f = (nn.LayerNorm if not rms_norm else RMSNorm)(
            d_model, eps=norm_epsilon, **factory_kwargs
        )

        self.apply(
            partial(
                _init_weights,
                n_layer=n_layer,
                **(initializer_cfg if initializer_cfg is not None else {}),
            )
        )

    def allocate_inference_cache(self, batch_size, max_seqlen, dtype=None, **kwargs):
        return {
            i: layer.allocate_inference_cache(batch_size, max_seqlen, dtype=dtype, **kwargs)
            for i, layer in enumerate(self.layers)
        }

    def forward(self, input_ids, inference_params=None):
        hidden_states = self.embedding(input_ids)
        residual = None
        for layer in self.layers:
            hidden_states, residual = layer(
                hidden_states, residual, inference_params=inference_params
            )
        if not self.fused_add_norm:
            residual = (hidden_states + residual) if residual is not None else hidden_states
            hidden_states = self.norm_f(residual.to(dtype=self.norm_f.weight.dtype))
        else:
            # Set prenorm=False here since we don't need the residual
            fused_add_norm_fn = rms_norm_fn if isinstance(self.norm_f, RMSNorm) else layer_norm_fn
            hidden_states = fused_add_norm_fn(
                hidden_states,
                self.norm_f.weight,
                self.norm_f.bias,
                eps=self.norm_f.eps,
                residual=residual,
                prenorm=False,
                residual_in_fp32=self.residual_in_fp32,
            )
        return hidden_states


class MambaLMHeadModel(PreTrainedModel, GenerationMixin):
    config_class = MambaConfig

    def __init__(
        self,
        config,
        initializer_cfg=None,
        pad_vocab_size_multiple: int = 1,
        device=None,
        dtype=None,
        **backbone_kwargs,
    ) -> None:
        super().__init__(config)
        d_model = config.d_model
        n_layer = config.n_layer
        vocab_size = config.vocab_size
        factory_kwargs = {"device": device, "dtype": dtype}

        if vocab_size % pad_vocab_size_multiple != 0:
            vocab_size += pad_vocab_size_multiple - (vocab_size % pad_vocab_size_multiple)
        self.backbone = MixerModel(
            d_model=d_model,
            n_layer=n_layer,
            vocab_size=vocab_size,
            initializer_cfg=initializer_cfg,
            **backbone_kwargs,
            **factory_kwargs,
        )
        self.lm_head = nn.Linear(d_model, vocab_size, bias=False, **factory_kwargs)

        # Initialize weights and apply final processing
        self.apply(
            partial(
                _init_weights,
                n_layer=n_layer,
                **(initializer_cfg if initializer_cfg is not None else {}),
            )
        )
        self.tie_weights()
        # _tied_weights_keys = ['lm_head.weight']

    def tie_weights(self):
        self.lm_head.weight = self.backbone.embedding.weight

    def allocate_inference_cache(self, batch_size, max_seqlen, dtype=None, **kwargs):
        return self.backbone.allocate_inference_cache(batch_size, max_seqlen, dtype=dtype, **kwargs)

    def forward(
            self,
            input_ids,
            position_ids=None,
            inference_params=None,
            num_last_tokens=0,
            labels=None):
        """
        "position_ids" is just to be compatible with Transformer generation. We don't use it.
        num_last_tokens: if > 0, only return the logits for the last n tokens
        """
        hidden_states = self.backbone(input_ids, inference_params=inference_params)
        if num_last_tokens > 0:
            hidden_states = hidden_states[:, -num_last_tokens:]
        lm_logits = self.lm_head(hidden_states)

        loss = None
        if labels is not None:
            logits = lm_logits
            # Shift so that tokens < n predict n
            shift_logits = logits[..., :-1, :].contiguous()
            shift_labels = labels[..., 1:].contiguous()
            # Flatten the tokens
            loss_fct = CrossEntropyLoss()
            shift_logits = shift_logits.view(-1, self.config.vocab_size)
            shift_labels = shift_labels.view(-1)
            # Enable model parallelism
            shift_labels = shift_labels.to(shift_logits.device)
            loss = loss_fct(shift_logits, shift_labels)
            return (loss,)

        else:
            CausalLMOutput = namedtuple("CausalLMOutput", ["logits"])
            return CausalLMOutput(logits=lm_logits)


def train(model_args, data_args, args):

    # Get the total number of GPUs available
    world_size = int(os.environ.get('WORLD_SIZE', 1))

    # Get the rank of the current process
    rank = int(os.environ.get('RANK', 0))

    # Get the local rank (GPU device index)
    local_rank = int(os.environ.get('LOCAL_RANK', 0))

    seed = args.seed
    set_seed(seed)

    torch.cuda.set_device(local_rank)


    import torch
    from torch.utils.data import DataLoader
    import accelerate
    import transformers
    import logging

    logging.basicConfig(level=logging.DEBUG)

    print(accelerate.__version__, transformers.__version__)

    torch.cuda.set_device(int(get_device_str.split(':')[-1]))
    local_rank = os.environ['LOCAL_RANK']
    node_rank = os.environ['NODE_RANK']
    print(f'node_rank: {node_rank}, local_rank: {local_rank}')

    from streaming.base.format.mds.encodings import Encoding, _encodings
    from streaming import LocalDataset
    import streaming

    dtype = torch.bfloat16

    with deepspeed.zero.Init(dtype=dtype, enabled=True):
        model = MambaLMHeadModel.from_pretrained(
            model_args.model_name_or_path,
            )


    class UInt16(Encoding):
        def encode(self, obj) -> bytes:
            return obj.tobytes()

        def decode(self, data: bytes):
            return np.frombuffer(data, np.uint16)

    _encodings['uint16'] = UInt16

    class DatasetFixed(torch.utils.data.Dataset):
        def __init__(self, remote):

            streaming.base.util.clean_stale_shared_memory()
            self.dataset = LocalDataset(local=remote)

        def __getitem__(self, idx):
            data = self.dataset[idx]
            data['labels'] = data['input_ids'].copy()

            data.pop('token_type_ids', None)

            for k in data.keys():
                data[k] = data[k].astype(np.int64)
            return data

        def __len__(self):
            return len(self.dataset)

    directory = model_args.model_name_or_path.replace('/', '-')
    output_dir = os.path.join(data_args.share_directory, directory)

    train_dataset = DatasetFixed(remote=data_args.train_file)

    # https://github.com/mosaicml/streaming/issues/307#issuecomment-1729829065
    def inf_loop_dataloader(dataloader: torch.utils.data.DataLoader):
        while True:
            for batch in dataloader:
                yield batch

    sampler = torch.utils.data.DistributedSampler(
        train_dataset, shuffle=True, seed=seed, rank=rank, num_replicas=world_size,
        drop_last=True
    )

    dataloader = DataLoader(
        train_dataset, sampler=sampler, collate_fn=default_data_collator,
        batch_size=args.batch_size, pin_memory=True,drop_last=True
    )

    dataset_iterator = iter(inf_loop_dataloader(dataloader))
    batch = next(iter(dataset_iterator))

    no_decay = ["bias", "LayerNorm.weight", "layer_norm.weight"]
    optimizer_grouped_parameters = [{
        "params": [p for n, p in model.named_parameters() if not any(nd in n for nd in no_decay)],
        "weight_decay": args.weight_decay,
      },{
        "params": [p for n, p in model.named_parameters() if any(nd in n for nd in no_decay)],
        "weight_decay": 0.0,
      }] 

    optimizer = torch.optim.AdamW(optimizer_grouped_parameters, lr=args.learning_rate)
    
    # Scheduler and math around the number of training steps.
    overrode_max_train_steps = False
    num_update_steps_per_epoch = math.ceil(len(train_dataloader) / args.gradient_accumulation_steps)
    if dist.get_rank()==0:
        print(f"Number of update steps per epoch {num_update_steps_per_epoch}")
    if args.max_train_steps is None:
        args.max_train_steps = args.num_train_epochs * num_update_steps_per_epoch
        overrode_max_train_steps = True

    lr_scheduler = get_scheduler(
        name=args.lr_scheduler_type,
        optimizer=optimizer,
        num_warmup_steps=args.num_warmup_steps * args.gradient_accumulation_steps,
        num_training_steps=args.max_train_steps * args.gradient_accumulation_steps,
        )

    model, optimizer, _, _ = deepspeed.initialize(
        model=model,
        optimizer=optimizer,
        model_parameters=model.parameters(),
        config=args.deepspeed_config
    )

    device = torch.device(f"cuda:{local_rank}")
    for epoch in range(args.num_train_epochs):
        model.train()
        total_steps=0
        ds_loss = torch.zeros(2).to(local_rank)
    
    for epoch in range(args.num_train_epochs):
        model.train()
        total_steps=0
        ds_loss = torch.zeros(2).to(local_rank)

        for batch_idx, batch in enumerate(train_dataloader):
            batch = {k: v.to(device) for k, v in batch.items()}  
            output = model(**batch)
            if dist.get_rank() == 0: print(f"Processing training batch {batch_idx}")
            loss = output["loss"]
            loss.backward()
            ds_loss[0] += loss.item()
            ds_loss[1] += len(batch["input_ids"])
            optimizer.zero_grad()
            lr_scheduler.step()
            total_steps += 1
            if args.max_steps is not None and total_steps > args.max_steps:
                break
        
        torch.distributed.all_reduce(ds_loss, op=torch.distributed.ReduceOp.SUM)
        train_loss = ds_loss[0] / ds_loss[1]
        train_ppl = torch.exp(train_loss)

        if dist.get_rank()==0:
            print(f"******{epoch=}: {train_ppl=} {train_loss=}******")
        

    if dist.get_rank() == 0:
        print("Training done!")
    dist.barrier()


def main():

    parser = HfArgumentParser((ModelArguments, DataTrainingArguments, TrainingArgs))
    model_args, data_args, training_args = parser.parse_args_into_dataclasses()

    deepspeed.init_distributed(dist_backend=backend)  

 
    train(model_args, data_args, training_args)


if __name__ == "__main__":
    main()