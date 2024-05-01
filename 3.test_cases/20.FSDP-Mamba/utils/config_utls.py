from config import train_config


def update_config(config, args):
    if isinstance(config, (tuple,list)):
        for c in config:
            update_config(c, args)

    else:
        for k, v in vars(args).items():
            if hasattr(config, k):
                setattr(config, k, v)
            elif "." in k:
                config_name, param_name = k.split(".")
                if type(config).__name__ == config_name:
                    if hasattr(config, param_name):
                        setattr(config, param_name, v)
                    else:
                        print(f"Warning: {config_name} does not accept parameter: {k}")
            else:
                print(f"Warning: unknown parameter {k}")


