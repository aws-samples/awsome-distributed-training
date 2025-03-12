import nemo_run as run
import argparse
import math
import os
from functools import partial
from typing import Any, Optional
from nemo.collections import llm
from nemo.lightning.run import plugins
from nemo.collections.nlp.modules.common.tokenizer_utils import get_nmt_tokenizer


# python run.py --nodes 2 --max_steps 1000


def small_llama_cfg() -> llm.GPTConfig:
   """Small 180m model"""
   return run.Config(
       llm.Llama3Config8B,
       rotary_base=500_000,
       seq_length=1024,
       num_layers=12,
       hidden_size=768,
       ffn_hidden_size=2688,
       num_attention_heads=16,
       init_method_std=0.023,
   )


def get_parser():
   parser = argparse.ArgumentParser(description="NeMo 2.0 on SageMaker Hyperpod")
   parser.add_argument("--partition", type=str, help="Slurm partition to run on", default="dev")
   parser.add_argument("--nodes", type=int, help="Number of nodes to run on", default=1)
   parser.add_argument("--max_steps", type=int, help="Maximum number of steps", default=200)
   parser.add_argument("--account", type=str, help="Slurm account to use", default="ubuntu")
   parser.add_argument("--container_image", type=str, help="Container image to use", default="/fsx/ubuntu/aws-nemo-24-12.sqsh")
   parser.add_argument("--time", type=str, help="Time to run the job", default="01:00:00")

   return parser


def slurm_executor(
   account: str,
   partition: str,
   nodes: int,
   user: str = "local",
   host: str = "local",
   remote_job_dir: str = "/fsx/ubuntu/aws-nemo",
   time: str = "01:00:00",
   custom_mounts: Optional[list[str]] = None,
   custom_env_vars: Optional[dict[str, str]] = None,
   container_image: str = "/fsx/ubuntu/aws-nemo-24-12.sqsh",
   retries: int = 0,
) -> run.SlurmExecutor:
   if not (user and host and remote_job_dir and account and partition and nodes):
       raise RuntimeError(
           "Please set user, host, remote_job_dir, account, partition, nodes args for using this function."
       )


   # mounts = ["/a/b/c:/b/c"]
   mounts = []
   # Custom mounts are defined here.
   if custom_mounts:
       mounts.extend(custom_mounts)
   print(mounts)
   # Env vars for jobs are configured here
   env_vars = {
       "TORCH_NCCL_AVOID_RECORD_STREAMS": "1",
       "NVTE_DP_AMAX_REDUCE_INTERVAL": "0",
       "NVTE_ASYNC_AMAX_REDUCTION": "1",
       "NVTE_FUSED_ATTN": "0",
       "FI_EFA_USE_HUGE_PAGE": "0",
       # "LD_LIBRARY_PATH": "/usr/local/cuda-12.4/lib",
   }
   if custom_env_vars:
       env_vars |= custom_env_vars


   # This will package the train.py script in the current working directory to the remote cluster.
   # If you are inside a git repo, you can also use https://github.com/NVIDIA/NeMo-Run/blob/main/src/nemo_run/core/packaging/git.py.
   # If the script already exists on your container and you call it with the absolute path, you can also just use `run.Packager()`.
   packager = run.Packager()


   local_tunnel = run.LocalTunnel(job_dir="")
  
   # This defines the slurm executor.
   # We connect to the executor via the tunnel defined by user, host and remote_job_dir.
   # https://docs.nvidia.com/nemo-framework/user-guide/24.09/nemorun/guides/execution.html#slurmexecutor
   # https://github.com/NVIDIA/NeMo-Run/blob/7bca60a6d2af3eea1aba331d3a80a6d7351b6e84/nemo_run/core/execution/slurm.py#L99
   executor = run.SlurmExecutor(
       account=account,
       partition=partition,
       tunnel=local_tunnel,
       nodes=nodes,
       mem="0",
       exclusive=True,
       packager=packager,
   )


   executor.container_image = container_image
   executor.container_mounts = mounts
   executor.env_vars = env_vars
   executor.retries = retries
   executor.time = time


   return executor


if __name__ == "__main__":
   args = get_parser().parse_args()
  
   import random, string
   stri = ''.join(random.choice(string.ascii_uppercase + string.digits) for _ in range(5))
   exp_name = f"aws-nemo2"+stri
  
   pretrain_recipe = partial(llm.llama31_8b.pretrain_recipe, num_nodes=args.nodes)(name=exp_name, dir="")
   pretrain_recipe.trainer.num_sanity_val_steps = 0
   pretrain_recipe.model = run.Config(llm.LlamaModel, small_llama_cfg())
   pretrain_recipe.data.tokenizer = run.Config(get_nmt_tokenizer, library="megatron", model_name= "GPT2BPETokenizer", vocab_file="/root/.cache/torch/megatron/megatron-gpt-345m_vocab", merges_file="/root/.cache/torch/megatron/megatron-gpt-345m_merges")
   pretrain_recipe.broadcast(max_steps=args.max_steps)
   pretrain_recipe.trainer.limit_val_batches = 2
   pretrain_recipe.trainer.log_every_n_steps = 1
   pretrain_recipe.trainer.val_check_interval = 10


   # Run it locally
   executor = slurm_executor(
       partition=args.partition,
       account=args.account,
       nodes=args.nodes,
       container_image=args.container_image,
       time=args.time,
       custom_mounts=[
           "/fsx/ubuntu/megatron:/root/.cache/torch/megatron"
       ]
   )


   with run.Experiment(exp_name, log_level="INFO") as exp:
       exp.add(pretrain_recipe, executor=executor, tail_logs=True, name="training")
       # Run the experiment
       exp.run(detach=True)

