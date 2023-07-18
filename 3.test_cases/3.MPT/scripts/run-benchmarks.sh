#!/usr/bin/env bash
. config.env
# Prepare dataset
set_options

export PROFILE_FILE=/report/profile_file
run docker run \
  --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 \
  --rm \
  -i \
  -v $(pwd)/report:/report \
  --name llm-foundry \
  llm-foundry \
  /bin/bash -s <<EOF
cd /workspace/llm-foundry/scripts

# Convert C4 dataset to StreamingDataset format
python data_prep/convert_dataset_hf.py \
  --dataset c4 --data_subset en \
  --out_root my-copy-c4 --splits train_small val_small \
  --concat_tokens 2048 --tokenizer EleutherAI/gpt-neox-20b --eos_text '<|endoftext|>'

nsys sessions list
python -c "import streaming; streaming.base.util.clean_stale_shared_memory()"
# Train an MPT-7B model for 10 batches
nsys profile -w true -t cuda,nvtx,osrt,cudnn,cublas \
  --force-overwrite=true -s cpu --cudabacktrace=true -x true -o ${PROFILE_FILE} composer train/train.py \
  train/yamls/pretrain/mpt-7b.yaml \
  data_local=my-copy-c4 \
  train_loader.dataset.split=train_small \
  eval_loader.dataset.split=val_small \
  model.loss_fn=torch_crossentropy \
  max_duration=3ba \
  eval_interval=0 \
  save_folder=mpt-7b \
  device_train_microbatch_size=8 \
  global_train_batch_size=256
EOF
