from transformers.models.llama.configuration_llama import LlamaConfig
from transformers import MambaConfig

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
    elif model_name == "mamba2.8b":
        model_config = MambaConfig(
            hidden_size = 2560,
            initializer_range = 0.1,
            intermediate_size = 5120,
            n_layer = 64,
            num_hidden_layers = 64,
            state_size = 16,
            time_step_rank = 160,
            vocab_size = 50280
        )
    elif model_name == "mamba1.4b":
        model_config = MambaConfig(
            d_model = 2048,
            hidden_size = 2048,
            initializer_range = 0.1,
            intermediate_size = 4096,
            n_layer = 48,
            num_hidden_layers = 48,
            state_size = 16,
            time_step_rank = 128,
            vocab_size = 50280
        )
    elif model_name == "mamba790m":
        model_config = MambaConfig(
            d_model = 2048,
            hidden_size = 1536,
            initializer_range = 0.1,
            intermediate_size = 3072,
            n_layer = 48,
            num_hidden_layers = 48,
            state_size = 16,
            time_step_rank = 96,
            vocab_size = 50280
        )
    elif model_name == "mamba370m":
        model_config = MambaConfig(
            d_model = 1024,
            hidden_size = 1024,
            initializer_range = 0.1,
            intermediate_size = 2048,
            n_layer = 48,
            num_hidden_layers = 48,
            state_size = 16,
            time_step_rank = 64,
            vocab_size = 50280
        )
    elif model_name == "state-spaces/mamba-130m":
        model_config = MambaConfig(
            d_model = 1024,
            hidden_size = 1024,
            initializer_range = 0.1,
            intermediate_size = 2048,
            n_layer = 48,
            num_hidden_layers = 48,
            state_size = 16,
            time_step_rank = 64,
            vocab_size = 50280
        )

    else:
        raise ValueError(f"Model {model_name} currently not supported.")
    return model_config

