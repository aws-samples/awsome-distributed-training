## SMP v2 Examples
In this directory we have example scripts for training with SMP Pytorch. We assume you have already setup a conda environment with SMP Pytorch. Below we first describe the files in this directory, and then go over how to run some jobs.

### Files
- `train_lib.py` : Main training script
- `train.py` : Entrypoint to launch `train_lib.py`
- `scripts/model.sh` : Main script which passes the config and launches `train.py`. This is used by `conda_launch.sh` and scripts in convergence_jobs folder. If you want to define your own model configuration you might want to modify this.
- `arguments.py` : Parses arguments for the job. Please refer to this file for all the options the script supports.
- `checkpoints.py` : Handles saving and loading of checkpoints
- `data_pipeline.py`: Creates dataloaders for the job. Modify this file to load your own dataset.
- `delayed_param.py` : Delayed parameter initialization to init large models without OOM
- `learning_rates.py`, `train_utils.py`, `fsdp_utils.py`, `utils.py`, `memory_tracker.py` have utilities used by the main script.

#### Launch scripts
- `conda_launch.sh` : This is a slurm script which launches a job using the activated conda environment. It expects to be run on the master node of the Slurm cluster. See below section for instructions. By default it runs with synthetic data to make it easy to test the scripts.
- `convergence_jobs/neox_7b/neox_7b_4Mtokens.sh` : This is an example for launching a convergence job with slurm, an extension of `conda_launch.sh`

## Note on paths
These scripts need to be put on a directory that can be accessed on all nodes, such as FSX.
We also recommend setting all paths (for input data and checkpoints) as shared directories using FSX.
These paths can be set in scripts as shown in `convergence_jobs/neox_7b/neox_7b_4Mtokens.sh`.

## User Guide

1. Launching a job with synthetic data on 16 nodes. The default config in the script launches a 7B GPT NeoX model with synthetic data.
```
conda activate /PATH/TO/CONDA/ENV
sbatch -N 16 conda_launch.sh

# or

sbatch -N 16 conda_launch.sh /PATH/TO/CONDA/ENV
```

2. Changing arguments taken by the script.
`model.sh` takes certain arguments from the launch script, and uses them to pass args to the training script. You can refer to `model.sh` if those are the arguments you would like to change. For example, it takes the model size and sets the appropriate hidden_width,num_layers etc for the training script.

If model.sh doesn't take the argument but is taken by train_lib (arguments.py), you can still pass it to model.sh and the script will forward the arg. This is how the above script passes `--use_synthetic_data 1`.

3. To run with your own data
With the current dataloader in the script data needs to be prepared as json or json.gz (needs the arg  `--zipped_data 1`) files, where each file has a json line with input_ids and attention_mask in them. Please refer to data_pipeline.py for more. You can always replace with your own dataloader.
```
# 2a. modify the conda_launch.sh script with path to data
# 2b. start training
sbatch -N 16 conda_launch.sh /PATH/TO/CONDA/ENV
```

4. Running a convergence job or experiment
We have put together an example of a convergence script using the above referenced `scripts/model.sh` script. The script sets the model type, size, checkpointing directory, tensorboard directory for metrics, and other hyperparameters. This is a slurm script, used with sbatch similar to above.

```
sbatch -N 64 convergence_jobs/neox_7b/neox_7b_4Mtokens.sh
```
or
```
sbatch -N 64 --job-name neox_7b_4M_trial1 convergence_jobs/neox_7b/neox_7b_4Mtokens.sh
```

5. Resuming convergence job from a checkpoint
Modify the --resume_from_checkpoint arg with the path of the checkpoint. Then the job is started same as before.
```
sbatch -N 64 convergence_jobs/neox_7b/neox_7b_4Mtokens.sh
```

6. Running a finetuning job or experiment
In order to run a finetune experiment `--finetune 1` needs to be set. Either pretrained model name `--pretrained_model_name ` arg or a checkpoint file name `--pretrained_checkpoint_file` arg needs to be provided.

If `--pretrained_model_name ` is provided pretrained model config will be used for finetuning. If `--pretrained_model_name` is provided `--finetune_checkpoint_load_dir` also needs to be provided.

If `--finetune 1`  is set together with `--resume_from_checkpoint`, training will resume from the provided checkpoint.
