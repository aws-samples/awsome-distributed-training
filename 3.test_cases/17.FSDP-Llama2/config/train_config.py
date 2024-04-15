from dataclasses import dataclass

@dataclass
class training_config:

    model_name: str = "state-spaces/mamba-130m"
    load_ckpt_path: str = f"/fsx/{model_name}/ckpt"
    save_ckpt_path: str = f"/fsx/{model_name}/ckpt" 

    dataset_path: str = "/fsx/data/examples_datasets/wikicorpus_llama2_7B_tokenized_4k"
    seq_length: int = 4096
    sep_token: int = 1
    datasets: str = "lang=en/dataset=commoncrawl,lang=en/dataset=webhose,lang=en/dataset=github_clean,lang=de/dataset=wikipedia,lang=es/dataset=wikipedia,lang=fr/dataset=wikipedia,lang=ja/dataset=wikipedia,lang=pt/dataset=wikipedia,lang=en/dataset=wikimedia,lang=en/dataset=uspto,lang=en/dataset=pubmedcentral,lang=en/dataset=arxiv,lang=en/dataset=stackexchange,lang=en/dataset=PG19"
    weights: str = "7700,500,550,28,17,22,25,8,100,500,175,250,100,25"
    logical_shards: int = 768

    # fsdp policies
    mixed_precision: bool = True
    fsdp_activation_checkpointing: bool = True
    selective_checkpointing: int = 1
    sharding_strategy: str = "hsdp"
    low_cpu_fsdp: bool = False

    # training spec
    seed: int = 2023
    batch_size: int = 1
    num_steps: int = 2000000
    learning_rate: float = 3e-4
    grad_clip_thresh: float = 1.0

    # profiling and logging
    use_profiler: bool = False
    use_wandb: bool = False
    wandb_dir: str = f"/fsx/wandb/{model_name}-fsdp"
    wandb_project_name = f"training-{model_name}"
    wandb_run_id: str = "aabbccdd"  # give a unique id per job
    report_interval: int = 200
    checkpoint_interval: int = 20000

    # compile
    use_torch_compile: bool = False