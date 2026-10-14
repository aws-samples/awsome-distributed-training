# Hugging Face training with NVRx on Slurm

This example runs a normal GPT-2 training loop with PyTorch DDP or FSDP. One `sbatch` allocation starts one `ft_launcher` per node through `srun`. NVRx monitors real setup, update and checkpoint sections and restarts failed workers within that allocation. Fresh workers load the last completed PyTorch checkpoint and replay any unsaved updates. There is no Megatron dependency or external job controller.

## Requirements and build

Use an existing Slurm GPU partition, Pyxis/Enroot, a CUDA-13-compatible driver and a shared POSIX filesystem visible at the same absolute path on every node. The submitting UID must be able to write its run directory and the container's short node-local socket directory. Nodes must have working NCCL connectivity. The batch entry resolves the first node's Slurm `NodeAddr`, so PCS scheduler aliases need not resolve in DNS. The recipe assumes IPv4 or a DNS address, not an IPv6 literal.

From `examples/training/nvrx`, build the separate Slurm image:

```bash
docker build -f slurm/Dockerfile -t nvrx-slurm:single-allocation .
docker image inspect nvrx-slurm:single-allocation --format '{{.Id}}'
# On a host with Docker and Enroot 3.5:
enroot import -o nvrx-single-allocation.sqsh dockerd://nvrx-slurm:single-allocation
```

The image pins NVRx 0.7.0, PyTorch 2.9.0/cu130, CUDA 13.0.3/Ubuntu 24.04, Transformers 4.48.3 and EFA installer 1.50.0. EFA installation modifies container userspace only. Distribute this immutable squashfs to the same path on each node using your site's image workflow. Do not substitute the legacy Kubernetes image, requirements or deployment scripts.

## 0. Submit training

The synthetic `--tiny` fixture constructs a small two-layer GPT-2 and fixed int64 tokens locally. It needs no network, asset preparation or initial-checkpoint job. Replace the paths and partition below. The run directory must not exist; logs go beside it so they do not change that rule.

```bash
export NVRX_SOURCE_DIR=/shared/awsome-distributed-ai/examples/training/nvrx
export NVRX_RUN_DIR=/shared/nvrx/ddp-control
export NVRX_IMAGE=/local/images/nvrx-single-allocation.sqsh
export NVRX_MOUNTS=/shared:/shared
export NVRX_MAX_RESTARTS=2
export NVRX_SECTION_TIMEOUTS=setup:180,step:60,checkpointing:120
sbatch --parsable --partition=gpu --nodes=2 --gpus-per-node=8 \
  --output=/shared/nvrx/ddp-control-%j.out \
  "$NVRX_SOURCE_DIR/slurm/0.train.sbatch" --tiny --strategy=ddp \
  --max-steps=6 --checkpoint-interval=2
```

Record the returned job ID. This requests two exclusive nodes and 16 GPU workers for at most ten minutes, with no Slurm requeue. For one node, change `--nodes=1`; the launcher derives its fixed world from the allocation. Do not run two jobs against the same run directory. Stop an owned job with ordinary `scancel JOB_ID`. Nothing submits a successor.

For FSDP, choose a new `NVRX_RUN_DIR` and replace `--strategy=ddp` with `--strategy=fsdp`. Both strategies support float32 (default) and bfloat16 (`--dtype=bfloat16`); CPU tests support DDP/float32 only. Float16, quantized/frozen/mixed-dtype parameters and model classes other than `GPT2LMHeadModel` are not supported. FSDP uses one FULL_SHARD wrapper, appropriate for this reference rather than a large-model wrapping policy.

For real local inputs, replace `--tiny` with `--model-path /shared/models/gpt2 --tokens-path /shared/data/tokens.pt`. Supply a complete local Hugging Face `save_pretrained` GPT-2 directory and a trusted `torch.save` int64 tensor shaped `[samples, sequence_length]`. Samples must be nonempty, with at least two tokens, valid vocabulary IDs and a sequence within the model context. All tokens participate in causal-LM loss; prepack sequences rather than supplying padding masks. Keep those files unchanged for the whole run. No files are downloaded or hashed by the workers.

`NVRX_MOUNTS` must expose the run directory and any input paths. Pyxis retains the image's Python PATH and library paths; the batch entry explicitly forwards its launcher settings. Socket scratch defaults to `/opt/build-tmp` in the container. To change it, set `NVRX_LOCAL_TMPDIR` to a writable node-local path of at most 65 characters. Do not place sockets on the shared checkpoint filesystem.

## Worker recovery and checkpoints

Try an actual process failure with a new run directory and the same submission, adding `--fault-step=3 --fault-rank=1`. On the initial attempt only, that logical rank sends itself SIGKILL after update 3 and before saving it. With interval 2, all replacement ranks should log `LOADED step=2 cursor=2 restart=1`, replay update 3 and finish update 6. Fault injection is off unless requested.

`RankMonitorClient` sections in `src/train_slurm.py` bracket initialization, each forward/backward/optimizer update and each synchronous checkpoint. There is no background heartbeat that pretends a hung update is progressing. Tune section timeouts against measured work. `NVRX_MAX_RESTARTS=0` disables worker retries; otherwise the budget is finite, and the batch wall time is an additional bound. NVRx's own no-progress policy can stop retries earlier. No custom stop engine translates its decision into another job.

`src/slurm_checkpoint.py` saves model and AdamW state, the learning-rate scheduler, Python/NumPy/Torch/CUDA RNG and each logical rank's next batch cursor. DDP uses per-rank `torch.save` files. FSDP saves sharded model/optimizer state with PyTorch Distributed Checkpoint (DCP), plus per-rank extras. A rank always restores its own RNG and cursor even if the launcher's node placement changes. Resume requires the same world size, per-node GPU count, strategy, precision, inputs and update settings.

All ranks finish their writes before rank 0 atomically replaces `latest_checkpointed_iteration.txt`. That pointer is the only checkpoint selector and NVRx's progress input. An interrupted later `step_N` directory is not selected; a retry can finish writing that step. Checkpoints are retained, so budget storage for every save. This protocol covers worker failure, not storage corruption or physical power-loss durability. Missing or unreadable selected state fails the run; it never falls back to older weights or starts from zero. Arbitrary storage corruption is not detected. Load only trusted checkpoints: rank state uses Python pickle.

A failure before the first completed save has nothing to restore. NVRx may launch its remaining bounded retries, but they fail on the missing pointer without training from scratch or claiming progress. Diagnose the failure and choose a new run directory for a new attempt. There is no step-zero save or synthetic AdamW update.

For an explicit later invocation, pass `--resume` with the existing run directory and unchanged inputs/settings. The pointer must exist. The normal command needs no `--resume` change for an in-job NVRx restart: `TORCHELASTIC_RESTART_COUNT` selects the required-load path. A new invocation without `--resume` refuses an existing directory. Resuming an already finished target loads state and performs no further updates; increasing `--max-steps` continues training.

## Check results and limits

Use `squeue -j JOB_ID` and capture `scontrol show job JOB_ID` while available. Slurm accounting is not required. Inspect the batch output and `${NVRX_RUN_DIR}-logs/JOB_ID/node-*/` for every rank's `FRESH`/`LOADED`, `SAVED` and `DONE` lines. Successful submission is not successful training. The final pointer should match the requested update count, and a failure trial should be compared with a no-failure control on identical input, including optimizer, scheduler, RNG and cursor, not just weights.

The simplified code was exercised on AWS PCS (Slurm 25.05.9, Pyxis, Enroot 3.5.0), on two `g7.48xlarge` nodes with eight RTX PRO 4500 Blackwell Server Edition GPUs each. Four float32 `--tiny` jobs ran the batch entry above: a control and a SIGKILL/restart case for each strategy. All 16 ranks completed six updates; each failure case restored step 2 and completed within the same allocation. The final FSDP model/optimizer and rank state matched its control exactly. DDP model and optimizer maximum absolute differences were `2.27e-7` and `2.79e-9` (comparison `rtol=1e-5`, `atol=1e-6`); scheduler, RNG, cursor and AdamW counters matched exactly. DDP is numerically equivalent here, not bitwise identical. CPU and built-image supporting suites each passed all six tests. These are small recovery checks, not pretrained-model or bfloat16 GPU qualification.

The scope is bounded worker restart within one live Slurm allocation. Allocation loss, physical-node loss, node reboot, spare promotion, elastic world changes, B300/customer-scale operation, convergence and performance are not qualified or implemented here. The separate Kubernetes, asynchronous, local-checkpoint and in-process examples are unchanged.

## Supporting CPU tests

Use the pinned environment (or the image with no GPUs) from `examples/training/nvrx`. Set `TMPDIR` to a short, writable node-local directory if the system temporary path is long; the tests create and remove their socket directories there.

```bash
python -m pytest --noconftest tests -v
bash -n slurm/0.train.sbatch
bash -n slurm/1.launch.sh
```

The narrow tests cover new/resume directory rules, incomplete saves, missing or unreadable requested state, causal-LM token boundaries, real two-rank SIGKILL/restart with exact final training-state comparison, failure before the first checkpoint and a zero restart budget. They supplement rather than replace Slurm/DDP/FSDP target-hardware runs.

## Attribution

The monitor section pattern is adapted from NVIDIA's [NVRx v0.7.0 sections example](https://github.com/NVIDIA/nvidia-resiliency-ext/blob/ebf0352a82ca5699148ea10bec2b8eedd121e382/examples/fault_tolerance/train_ddp_sections_api.py), replacing its dummy workload with direct Hugging Face training and same-world checkpoint recovery. Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved. The original notice and Apache-2.0 terms are in [LICENSE.upstream.txt](LICENSE.upstream.txt).
