import json
from peft import LoraConfig, PeftModel
from transformers import AutoModelForCausalLM
import torch
import argparse
from safetensors import safe_open


def merge_lora_weights(args):
    base_model = AutoModelForCausalLM.from_pretrained(args.base_model_path)
    with open(args.adapter_config_path, "r") as f:
        config_dict = json.load(f)
    peft_config = LoraConfig(**config_dict)
    model = PeftModel(base_model, peft_config)
    
    lora_weights_tensors = {}
    with safe_open(args.lora_safetensors_path, framework="pt", device='cpu') as f:
        for k in f.keys():
            lora_weights_tensors[k] = f.get_tensor(k)
            
    for layer_name in list(lora_weights_tensors):
        if 'layer' in layer_name and 'lora' in layer_name:
            new_layer_name = layer_name.replace('weight', 'default.weight')
            lora_weights_tensors[new_layer_name] = lora_weights_tensors[layer_name].clone()
            del lora_weights_tensors[layer_name]
        else:
            del lora_weights_tensors[layer_name]

    updated_state_dict = model.state_dict().copy()
    for layer, weights in lora_weights_tensors.items():
        updated_state_dict[layer] = weights
    model.load_state_dict(updated_state_dict)    
    merged_model = model.merge_and_unload()    
    merged_model.save_pretrained(args.final_model_path, safe_serialization=True, max_shard_size="5GB")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--final_model_path", type=str)
    parser.add_argument("--adapter_config_path", type=str)
    parser.add_argument("--base_model_path", type=str)
    parser.add_argument("--lora_safetensors_path", type=str)
    args = parser.parse_args()
    merge_lora_weights(args)