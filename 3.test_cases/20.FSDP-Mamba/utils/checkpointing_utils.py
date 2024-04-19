import os
import shutil
import time
from pathlib import Path

import torch
from torch.distributed._shard.checkpoint import (
    FileSystemReader,
    FileSystemWriter,
    load_state_dict,
    save_state_dict,
)
from torch.distributed.checkpoint.default_planner import (
    DefaultLoadPlanner,
    DefaultSavePlanner,
)
from torch.distributed.checkpoint.optimizer import load_sharded_optimizer_state_dict
from torch.distributed.fsdp import FullStateDictConfig
from torch.distributed.fsdp import FullyShardedDataParallel as FSDP
from torch.distributed.fsdp import StateDictType


def get_latest(targdir, qualifier=lambda x: True):
    """Fetch the latest file or folder written to target directory, subject to name passing the qualifier fn.
    If directory is empty or nonexistent or no items qualify, return None."""
    if os.path.exists(targdir) and len(os.listdir(targdir)) > 0:
        latest = max(
            [
                os.path.join(targdir, x)
                for x in os.listdir(targdir)
                if qualifier(os.path.join(targdir, x))
            ],
            key=lambda path: int(path.split("/")[-1].split("_")[1]),
        )
        return os.path.join(targdir, latest)
    return None


def get_oldest(targdir, qualifier=lambda x: True):
    """Fetch the oldest file or folder written to target directory, subject to name passing the qualifier fn.
    If directory is empty or nonexistent or no items qualify, return None."""
    if os.path.exists(targdir) and len(os.listdir(targdir)) > 0:
        oldest = min(
            [
                os.path.join(targdir, x)
                for x in os.listdir(targdir)
                if qualifier(os.path.join(targdir, x))
            ],
            key=os.path.getctime,
        )
        return os.path.join(targdir, oldest)
    return None


class Checkpointer:
    """
    Manages the checkpoint directory. Saves new checkpoints and deletes old ones after the specified number are written.
    Also handles loading and saving of checkpoints in sharded and unsharded formats.
    Assumes model and optimizer inputs are in FSDP.
    ...
    Args
    ----
    ckpdir : str
        Absolute path to desired save location. Creates a new 'checkpoints/' subfolder at that location.
    n_to_save : int
        Number of volatile checkpoints to maintain at any given time.
    parallel_mode : str
        Write sharded folder ckps (when sharded: 'fsdp' or 'hsdp') or unsharded file ckps (when sharded: 'ddp')
    report_fn : Callable or None
        Optional function for reporting or logging status updates. Expected to handle arbitrary *args, **kwargs.
        Defaults to self._selective_print().

    Methods
    -------
    save : keyword args -> str | None
        Saves dictionary of keyword arg key/value pairs to specified checkpoint directory, deleting old checkpoints
        as necessary. If a checkpoint is deleted, returns the filename of that checkpoint.
    load :
        See docstring for individual function below
    """

    def __init__(
        self,
        ckpdir,
        n_to_save,
        parallel_mode,
        rank,
        local_rank,
        report_fn=None,
    ):
        self.max_ckps = n_to_save
        self.rank = rank
        self.local_rank = local_rank
        self.ckp_path = os.path.join(ckpdir, "checkpoints/")
        os.makedirs(self.ckp_path, exist_ok=True)
        self.p_mode = parallel_mode
        assert parallel_mode in ["fsdp", "hsdp", "ddp"]
        self.report = self._selective_print if report_fn is None else report_fn

    def _selective_print(self, *args, **kwargs):
        if self.rank == 0:
            print(*args)
            for k, v in kwargs.items():
                print(k, "=", v)

    def _cleanup(self):
        # Clean old checkpoints. Barrier to keep synchronization correct.
        file_to_remove = None
        if (
            self.rank == 0
            and len([x for x in os.listdir(self.ckp_path) if "tmp" in x])
            > self.max_ckps
        ):
            ckp_to_remove = Path(
                get_oldest(self.ckp_path, qualifier=lambda x: "tmp" in x)
            )
            if os.path.is_file(ckp_to_remove):
                ckp_to_remove.unlink()
            else:
                shutil.rmtree(ckp_to_remove)
        return file_to_remove

    def _do_save(self, rank, local_rank):  # , shard_group, replicate_group):
        if self.p_mode == "hsdp":
            return rank == local_rank
        else:
            return True
        # TODO: Distributed writing contingent upon the following fix: https://github.com/pytorch/pytorch/issues/104081
        # if not is_dist:
        #     return (rank == local_rank)
        # else:
        #     a = rank % shard_group.size()
        #     b = rank // shard_group.size()
        #     return True if a % replicate_group.size() == b else False
        # shard_group = model.process_group
        # replicate_group = model.__inter_node_state.process_group

    def _write(self, state_dict, loader_state, process_group, save_name, rank):
        os.makedirs(save_name, exist_ok=True)
        writer = FileSystemWriter(save_name, single_file_per_rank=True)
        if state_dict is not None:
            save_state_dict(
                state_dict=state_dict,
                storage_writer=writer,
                process_group=process_group,
                planner=DefaultSavePlanner(),
            )
        if loader_state is not None:
            loader_state.save_to_path(save_name)

    def _validate_ckp_path(self, path):
        """Interpret path to appropriate checkpoint. If found, return modified path. If not found, return None."""
        # Does path exist and is it non-empty?
        if os.path.exists(path):
            # Is this a file?
            if os.path.isfile(path):
                return path
            # Is this a sharded directory?
            elif "metadata.pth" in os.listdir(path):
                return path
            # Is this a path to a set of checkpoints?
            elif len(os.listdir(path)) > 0:
                latest = get_latest(path)
                if os.path.isfile(latest):
                    return latest
                elif "metadata.pth" in os.listdir(latest):
                    return latest
        return None

    def load(
        self, model, optimizer, dataloader, path="", reset_stepcount=False, strict=True
    ):
        """
        Handle checkpoint loading for model/optimizer/dataloader from given path, according to arguments.
        Defaults to save path for locating an appropriate checkpoint. If a path is provided, will use
        it only if no appropriate checkpoint is found in the save path (in which case it's a job restart).
        Reset_stepcount manually resets optimizer and dataloader states, and stat tracking.
        Strict determines whether to use strict loading or not FOR SINGLEFILE LOADING ONLY.
        Returns model, optimizer, dataloader, current step, and current tokens seen.
        """
        if self._validate_ckp_path(self.ckp_path) is not None:
            path = self.ckp_path
            reset_stepcount = False
        load_path = self._validate_ckp_path(path)
        if load_path is None:
            self.report(
                f"No valid checkpoint detected at {path}, starting from scratch."
            )
            return model, optimizer, dataloader, 0, 0
        else:
            self.report(f"Prior checkpoint {load_path} detected.")
            model_load_time = time.time()
            if os.path.isfile(load_path):
                checkpoint_data = torch.load(load_path, map_location="cpu")
                model.load_state_dict(checkpoint_data.get("model_state"), strict=strict)
                model.to(self.local_rank)
                self.report(
                    f"Checkpoint {load_path} is a single-file checkpoint containing only a model. Optimizer and dataloader are from scratch.",
                    model_load_time=time.time() - model_load_time,
                )
                return model, optimizer, dataloader, 0, 0
            else:
                # Load model
                with FSDP.state_dict_type(model, StateDictType.SHARDED_STATE_DICT):
                    state_dict = model.state_dict()
                    model_ckp = {"model_state": state_dict}
                    load_state_dict(
                        state_dict=model_ckp,
                        storage_reader=FileSystemReader(load_path),
                        planner=DefaultLoadPlanner(),
                    )
                    model.load_state_dict(model_ckp["model_state"])
                model.to(self.local_rank)
                self.report(model_load_time=time.time() - model_load_time)
                step = 0
                ntok = 0
                # Load metadata
                if not reset_stepcount:
                    metadata = torch.load(os.path.join(load_path, "metadata.pth"))
                    step = metadata.get("step", 0)
                    ntok = metadata.get("tokens_seen", 0)
                    self.report("Metadata loaded", start_step=step, n_tokens_seen=ntok)
                # Load optimizer
                if optimizer is not None:
                    optim_load_time = time.time()
                    with FSDP.state_dict_type(model, StateDictType.SHARDED_STATE_DICT):
                        optim_state = load_sharded_optimizer_state_dict(
                            model_state_dict=model.state_dict(),
                            optimizer_key="optimizer_state",
                            storage_reader=FileSystemReader(load_path),
                        )
                    flattened_osd = FSDP.optim_state_dict_to_load(
                        model, optimizer, optim_state["optimizer_state"]
                    )
                    optimizer.load_state_dict(flattened_osd)
                    self.report(optimizer_load_time=time.time() - optim_load_time)
                else:
                    self.report("Skipping optimizer load, no optimizer provided.")
                # Load dataset
                if dataloader is not None:
                    data_load_time = time.time()
                    dataloader.dataset.load_from_path(load_path)
                    self.report(dataset_load_time=time.time() - data_load_time)
                else:
                    self.report("Skipping dataset load, no dataloader provided.")
                return model, optimizer, dataloader, step, ntok

    def save(
        self,
        step,
        model,
        optimizer,
        dataloader,
        **kwargs,
    ):
        # Note: metadata kwargs cannot contain any of:
        # (step, model, optimizer, dataloader)
        rank = self.rank
        save_time = time.time()
        with FSDP.state_dict_type(model, StateDictType.SHARDED_STATE_DICT):
            model_state = model.state_dict()
            optim_state = FSDP.sharded_optim_state_dict(model, optimizer)
        dataloader_state = dataloader.dataset

        save_name = os.path.join(self.ckp_path, "step_" + str(step) + "_ckp")
        state_dict = {"model_state": model_state, "optimizer_state": optim_state}
        if self._do_save(rank, self.local_rank):
            self._write(
                state_dict, dataloader_state, model.process_group, save_name, rank
            )
        else:
            self._write(None, dataloader_state, None, save_name, rank)
        if rank == 0:
            metadata = kwargs
            metadata["step"] = step
            torch.save(metadata, os.path.join(save_name, "metadata.pth"))
        self.report(
            f"Checkpoint saved in {save_name}", model_save_time=time.time() - save_time
        )

        return self._cleanup()

    def save_single_file(
        self,
        step,
        model,
        **kwargs,
    ):
        # Note: metadata kwargs cannot contain any of:
        # (step, model)
        save_name = os.path.join(self.ckp_path, "step_" + str(step) + "_ckp.pth")
        save_time = time.time()
        with FSDP.state_dict_type(
            model,
            StateDictType.FULL_STATE_DICT,
            FullStateDictConfig(offload_to_cpu=True, rank0_only=True),
        ):
            model_state = model.state_dict()
        if self.rank == 0:
            metadata = kwargs
            metadata["step"] = step
            metadata["model_state"] = model_state
            torch.save(metadata, save_name)
        self.report("Checkpoint written", model_save_time=time.time() - save_time)

        return self._cleanup()