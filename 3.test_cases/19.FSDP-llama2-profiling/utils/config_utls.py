from transformers.models.llama.configuration_llama import LlamaConfig

from config import train_config


def update_config(config, **kwargs):
    if isinstance(config, (tuple,list)):
        for c in config:
            update_config(c, **kwargs)

    else:
        for k, v in kwargs.items():
            if hasattr(config, k):
                setattr(config, k, v)
            elif "." in k:
                config_name, param_name = k.split(".")
                if type(config).__name__ == config_name:
                    if hasattr(config, param_name):
                        setattr(config, param_name, v)
                    else:
                        print(f"Warning: {config_name} does not accept parameter: {k}")
            elif isinstance(config, train_config):
                print(f"Warning: unknown parameter {k}")

def get_model_config(model_name):
    if model_name == "llama2_70b":
        model_config = LlamaConfig(
            hidden_size=8192,
            initializer_range= 0.02,
            max_position_embeddings=4096,
            num_attention_heads=64,
            num_key_value_heads=8,
            num_hidden_layers=80,
            intermediate_size=28762,
            vocab_size=32000            
        )
    elif model_name == "llama2_13b":
        model_config = LlamaConfig(
            hidden_size=5120,
            initializer_range= 0.02,
            max_position_embeddings=4096,
            num_attention_heads=40,
            num_key_value_heads=40,
            num_hidden_layers=40,
            intermediate_size=13824,
            vocab_size=32000            
        )
    elif model_name == "llama2_7b":
        model_config = LlamaConfig(
            hidden_size=4096,
            initializer_range= 0.02,
            max_position_embeddings=4096,
            num_attention_heads=32,
            num_key_value_heads=32,
            num_hidden_layers=32,
            intermediate_size=11008,
            vocab_size=32000            
        )
    else:
        raise ValueError(f"Model {model_name} currently not supported.")
    return model_config

