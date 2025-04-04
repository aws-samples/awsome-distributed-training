import argparse
import json
from pathlib import Path
from huggingface_hub import split_torch_state_dict_into_shards
from safetensors.torch import save_file
from optimum.neuron.distributed.checkpointing import consolidate_model_parallel_checkpoints
import torch

def custom_consolidate_to_unified_checkpoint(checkpoint_dir: str, output_dir: str, save_format: str = "safetensors"):
    output_dir.mkdir(parents=True, exist_ok=True)
    state_dict = consolidate_model_parallel_checkpoints(checkpoint_dir)
    for key, value in state_dict.items():
        if isinstance(value, torch.Tensor):
            state_dict[key] = value.contiguous()

    split_result = split_torch_state_dict_into_shards(state_dict, max_shard_size="5GB")
    # Save shards
    for shard_file, shard_tensors in split_result.filename_to_tensors.items():
        shard_dict = {name: state_dict[name] for name in shard_tensors}
        shard_path = output_dir / shard_file
        if save_format == "safetensors":
            save_file(shard_dict, shard_path, metadata={"format": "pt"})
        else:
            torch.save(shard_dict, shard_path)

    index = {
        "metadata": split_result.metadata,
        "weight_map": split_result.tensor_to_filename
    }
    
    index_file = "model.safetensors.index.json" if save_format == "safetensors" else "pytorch_model.bin.index.json"
    with open(output_dir / index_file, "w") as f:
        json.dump(index, f, indent=2)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input_dir", type=str, required=True)
    parser.add_argument("--output_dir", type=str, required=True)
    parser.add_argument("--save_format", type=str, choices=["safetensors", "pytorch"])
    args = parser.parse_args()
    output_dir = Path(args.output_dir)
    checkpoint_dir = Path(args.input_dir) / "adapter_shards"
    custom_consolidate_to_unified_checkpoint(
        checkpoint_dir=checkpoint_dir,
        output_dir=output_dir,
        save_format=args.save_format
    )