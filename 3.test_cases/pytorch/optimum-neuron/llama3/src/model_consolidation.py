import shutil
from pathlib import Path
import torch
from safetensors.torch import save_file
from huggingface_hub import split_torch_state_dict_into_shards
import json
from optimum.neuron.distributed.checkpointing import consolidate_model_parallel_checkpoints
import argparse

def custom_consolidate_to_unified_checkpoint(
    checkpoint_dir: Path,
    output_dir: Path,
    save_format: str = "safetensors",
):
    """
    Consolidates sharded checkpoints into a unified format.
    
    Args:
        checkpoint_dir (Path): Directory containing sharded checkpoints
        output_dir (Path): Directory where consolidated checkpoint will be saved
        save_format (str): Format to save the checkpoint ('safetensors' or 'pytorch')
    """
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Consolidating checkpoints from {checkpoint_dir}")
    state_dict = consolidate_model_parallel_checkpoints(checkpoint_dir)

    # Make tensors contiguous for better memory efficiency
    for key, value in state_dict.items():
        if isinstance(value, torch.Tensor):
            state_dict[key] = value.contiguous()

    print("Splitting state dict into shards...")
    split_result = split_torch_state_dict_into_shards(state_dict, max_shard_size="5GB")
    
    # Save shards
    for shard_file, shard_tensors in split_result.filename_to_tensors.items():
        shard_dict = {name: state_dict[name] for name in shard_tensors}
        shard_path = output_dir / shard_file
        
        print(f"Saving shard: {shard_path}")
        if save_format == "safetensors":
            save_file(shard_dict, shard_path, metadata={"format": "pt"})
        else:
            torch.save(shard_dict, shard_path)

    # Create and save index
    index = {
        "metadata": split_result.metadata,
        "weight_map": split_result.tensor_to_filename
    }
    
    index_file = "model.safetensors.index.json" if save_format == "safetensors" else "pytorch_model.bin.index.json"
    with open(output_dir / index_file, "w") as f:
        json.dump(index, f, indent=2)
    print(f"Created index file: {output_dir / index_file}")

def copy_additional_files(input_dir: Path, output_dir: Path):
    """
    Copies model configuration and tokenizer files.
    
    Args:
        input_dir (Path): Source directory containing the files
        output_dir (Path): Destination directory for the files
    """
    files_to_copy = [
        "config.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "special_tokens_map.json",
        "tokenizer.model"
    ]

    for file in files_to_copy:
        src = input_dir / file
        dst = output_dir / file
        if src.exists():
            shutil.copy2(src, dst)
            print(f"Copied {file} to {dst}")
        else:
            print(f"Note: {file} not found in {input_dir}")

def main():
    parser = argparse.ArgumentParser(description="Consolidate model checkpoints")
    parser.add_argument("--input_dir", type=str, required=True, 
                      help="Path to the input directory containing the 'shards' folder")
    parser.add_argument("--output_dir", type=str, required=True, 
                      help="Path to the output directory for the consolidated checkpoint")
    parser.add_argument("--save_format", type=str, choices=["safetensors", "pytorch"], 
                      default="safetensors", help="Format to save the consolidated checkpoint")

    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)

    # Construct path to shards directory
    checkpoint_dir = input_dir / "adapter_shards"
    if not checkpoint_dir.exists():
        raise ValueError(f"Shards directory not found at: {checkpoint_dir}")

    # Consolidate checkpoints
    try:
        custom_consolidate_to_unified_checkpoint(
            checkpoint_dir=checkpoint_dir,
            output_dir=output_dir,
            save_format=args.save_format
        )
    except Exception as e:
        print(f"Error during checkpoint consolidation: {e}")
        return

    # Copy configuration files
    try:
        copy_additional_files(input_dir, output_dir)
    except Exception as e:
        print(f"Error copying additional files: {e}")

if __name__ == "__main__":
    main()