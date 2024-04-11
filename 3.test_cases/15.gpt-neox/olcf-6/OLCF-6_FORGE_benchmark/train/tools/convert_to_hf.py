# Copyright (c) 2021, EleutherAI
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

import os
import sys

import yaml
import argparse
from tqdm import tqdm

import torch
from transformers import GPTNeoXConfig, GPTNeoXForCausalLM
from typing import List

sys.path.append(
    os.path.abspath(os.path.join(os.path.dirname(__file__), os.path.pardir))
)
from megatron.tokenizer import build_tokenizer


"""
A script for converting saved NeoX Checkpoints to Huggingface (HF) compatible GPT-NeoX type models.

Note that this script does not support all NeoX features.
Please investigate carefully whether your model is compatible with all architectures supported by the GPTNeoXForCausalLM class in HF.

(e.g. position embeddings such as AliBi may not be supported by Huggingface's GPT-NeoX architecture.
"""


def load_partitions(
    input_checkpoint_path, mp_partitions, layer_idx
) -> List[torch.Tensor]:
    """Returns a list containing all weights in a given layer from a model (across MP partitions)"""

    loaded_tp_ranks = [
        torch.load(
            os.path.join(
                input_checkpoint_path,
                f"layer_{layer_idx:02}-model_{i:02}-model_states.pt",
            )
        )
        for i in range(mp_partitions)
    ]

    return loaded_tp_ranks


def get_key(loaded_config, key, default=None):
    """
    Search for a given key in a NeoX yaml. normalizes underscores -> hyphens
    """
    key = key.replace("_", "-")
    try:
        return loaded_config[key]
    except KeyError:
        key = key.replace("-", "_")
        try:
            return loaded_config[key]
        except KeyError:
            return default


def create_config(neox_config):
    """take in a loaded yaml from NeoX and assign relevant values to HF config.
    Returns: GPTNeoXConfig() object
    """

    class TokenizerArgs:
        # kinda hacky.
        # this is to get something with the same interface as is used in build_tokenizer()
        # without diving into loading a neox_args object or using argparse etc.
        def __init__(self, neox_config):
            self.make_vocab_size_divisible_by = get_key(
                neox_config, "make-vocab-size-divisible-by", default=128
            )
            self.model_parallel_size = get_key(neox_config, "model-parallel-size")
            self.vocab_file = get_key(neox_config, "vocab-file")
            self.merge_file = get_key(neox_config, "merge-file")
            self.tokenizer_type = get_key(neox_config, "tokenizer-type")

            self.rank = 0

    args = TokenizerArgs(neox_config)
    tokenizer = build_tokenizer(args)
    try:  # GPT2TokenizerFast raises NotImplementedError
        pad_token = tokenizer.pad
    except:
        pad_token = (
            1  # pad defaulting to 1. follows convention from GPT-NeoX-20b tokenizer
        )

    # TODO: change the default value here based on discussion regarding `gpt_j_tied` config parameter's default
    use_tied_lns = get_key(neox_config, "gpt-j-tied", False)

    if use_tied_lns:
        raise NotImplementedError(
            """ERROR: Huggingface Transformers does not yet support a single shared layernorm
                per transformer block for GPT-NeoX models trained  w/ GPT-J parallel residuals.
                See https://github.com/EleutherAI/gpt-neox/pull/481 for further details."""
        )

    # set all config values.
    hf_config = GPTNeoXConfig(
        vocab_size=args.padded_vocab_size,
        hidden_size=get_key(neox_config, "hidden-size"),
        num_hidden_layers=get_key(neox_config, "num-layers"),
        num_attention_heads=get_key(neox_config, "num-attention-heads"),
        intermediate_size=(get_key(neox_config, "hidden-size") * 4),
        hidden_act=get_key(neox_config, "activation", default="gelu"),
        rotary_pct=get_key(neox_config, "rotary-pct", default=1.0),
        rotary_emb_base=get_key(neox_config, "rotary-emb-base", default=10000),
        max_position_embeddings=get_key(neox_config, "max-position-embeddings"),
        initializer_range=get_key(neox_config, "init-method-std", 0.02),
        layer_norm_eps=get_key(neox_config, "layernorm-epsilon", 1e-5),
        use_cache=True,
        bos_token_id=tokenizer.eod,
        eos_token_id=tokenizer.eod,
        tie_word_embeddings=(not get_key(neox_config, "no-weight-tying", False)),
        use_parallel_residual=get_key(neox_config, "gpt-j-residual", False),
    )
    return hf_config


def convert(input_checkpoint_path, loaded_config, output_checkpoint_path):
    """convert a NeoX checkpoint to a HF model format.
    should perform model-parallel merging correctly
    but only supports features allowed by HF GPT-NeoX implementation (e.g. rotary embeddings)
    """

    hf_config = GPTNeoXConfig()

    hf_config = create_config(loaded_config)

    hf_model = GPTNeoXForCausalLM(
        hf_config
    ).half()  # nice-to-have: lazy init weights somehow?

    mp_partitions = get_key(loaded_config, "model-parallel-size")

    ### Embedding layer ###
    loaded_tp_ranks = load_partitions(input_checkpoint_path, mp_partitions, 0)
    hf_model.gpt_neox.embed_in.load_state_dict(
        {
            "weight": torch.cat(
                [t["word_embeddings.weight"] for t in loaded_tp_ranks], dim=0
            )
        }
    )

    assert (
        hf_config.vocab_size == hf_model.gpt_neox.embed_in.weight.shape[0]
    ), f"ERROR: calculated vocab size {hf_config.vocab_size} != embed param size {hf_model.gpt_neox.embed_in.shape[0]}"
    ### End Embedding Layer ###

    for layer_i in tqdm(range(get_key(loaded_config, "num-layers"))):

        # get layer from hf model
        hf_layer = hf_model.gpt_neox.layers[layer_i]

        # + 2 bc of embed layer and a dummy _pre_transformer_block
        loaded_tp_ranks = load_partitions(
            input_checkpoint_path, mp_partitions, layer_i + 2
        )

        state_dict = {}
        for key in [
            "attention.dense.weight",
            "mlp.dense_4h_to_h.weight",
        ]:
            state_dict[key] = torch.cat([t[key] for t in loaded_tp_ranks], dim=1)

        # average layernorm stats over mp ranks
        for key in [
            "input_layernorm.weight",
            "input_layernorm.bias",
            "post_attention_layernorm.weight",
            "post_attention_layernorm.bias",
        ]:
            state_dict[key] = (sum([t[key] for t in loaded_tp_ranks])) / len(
                loaded_tp_ranks
            )

        # LinearWithTPMerge
        for key in [
            "mlp.dense_h_to_4h.weight",
            "mlp.dense_h_to_4h.bias",
            "attention.query_key_value.weight",
            "attention.query_key_value.bias",
        ]:
            state_dict[key] = torch.cat([t[key] for t in loaded_tp_ranks], dim=0)

        # LinearWithTPSplitBias
        for key in [
            "mlp.dense_4h_to_h.bias",
            "attention.dense.bias",
        ]:
            state_dict[key] = sum([t[key] for t in loaded_tp_ranks])

        # Just take one
        state_dict["attention.rotary_emb.inv_freq"] = loaded_tp_ranks[0][
            "attention.rotary_emb.inv_freq"
        ]
        state_dict["attention.bias"] = hf_layer.state_dict()["attention.bias"]
        state_dict["attention.masked_bias"] = hf_layer.state_dict()[
            "attention.masked_bias"
        ]

        # load state_dict into layer
        hf_layer.load_state_dict(state_dict)

    # Load final layer norm
    loaded_tp_ranks = load_partitions(
        input_checkpoint_path, mp_partitions, get_key(loaded_config, "num-layers") + 3
    )

    hf_model.gpt_neox.final_layer_norm.load_state_dict(
        {
            "weight": (sum([t["norm.weight"] for t in loaded_tp_ranks]))
            / len(loaded_tp_ranks),
            "bias": (sum([t["norm.bias"] for t in loaded_tp_ranks]))
            / len(loaded_tp_ranks),
        }
    )
    del loaded_tp_ranks

    # Load output embedding
    loaded_tp_ranks = load_partitions(
        input_checkpoint_path, mp_partitions, get_key(loaded_config, "num-layers") + 4
    )

    hf_model.embed_out.load_state_dict(
        {
            "weight": torch.cat(
                [t["final_linear.weight"] for t in loaded_tp_ranks], dim=0
            ),
        }
    )

    del loaded_tp_ranks

    return hf_model


if __name__ == "__main__":

    # before running script:
    # `pip install --upgrade transformers`
    # `huggingface-cli login`
    #
    from huggingface_hub import create_repo, HfApi

    parser = argparse.ArgumentParser(
        description="Merge MP partitions and convert to HF Model."
    )
    parser.add_argument(
        "--input_dir",
        type=str,
        help="Path to NeoX checkpoint, e.g. /path/to/model/global_step143000",
    )
    parser.add_argument(
        "--config_file",
        type=str,
        help="Path to config file for the input NeoX checkpoint.",
    )
    parser.add_argument(
        "--output_dir",
        type=str,
        help="Output dir, where to save the HF Model, tokenizer, and configs",
    )
    parser.add_argument(
        "--upload",
        action="store_true",
        help="Set to true in order to upload to the HF Hub directly.",
    )
    args = parser.parse_args()

    with open(args.config_file) as f:
        loaded_config = yaml.full_load(f)

    hf_model = convert(args.input_dir, loaded_config, args.output_dir)

    hf_model.save_pretrained(args.output_dir)

    # save tokenizer to directory as well, for easy loading of model as a HF model
    tokenizer_type = get_key(loaded_config, "tokenizer-type")

    if tokenizer_type == "HFTokenizer":
        print(f"saving tokenizer from file {get_key(loaded_config, 'vocab-file')}")
        from transformers import PreTrainedTokenizerFast

        tokenizer = PreTrainedTokenizerFast(
            tokenizer_file=get_key(loaded_config, "vocab-file")
        )
        print("loaded tokenizer: ", tokenizer)
        tokenizer.save_pretrained(args.output_dir)
        print("tokenizer saved!")

    if args.upload:
        repo_name = input("Provide a repository name for the HF Hub: ")
        create_repo(repo_name, repo_type="model", private=False, use_auth_token=True)

        api = HfApi()
        api.upload_folder(
            folder_path=args.output_dir,
            repo_id=repo_name,
            repo_type="model",
        )
