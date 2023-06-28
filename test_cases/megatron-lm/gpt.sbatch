#!/bin/bash
#SBATCH --nodes=24
#SBATCH --job-name=megatron_gpt
#SBATCH --output=/admin/ubuntu/megatron-lm/joblogs/job-%j-%x.out
#SBATCH --gpus-per-node=8
#SBATCH --gres=gpu:8
#SBATCH --exclusive
#SBATCH --wait-all-nodes=1

### Disable hyperthreading by setting the tasks per core to 1
#SBATCH --ntasks-per-core=1

set -ex;
OUT_PREFIX=/admin/ubuntu/megatron-lm/joblogs/job-$SLURM_JOB_ID

# .sqsh file produced by docker-nvidia-pytorch-efa-aws-nccl/prepare-image.sh
: "${IMAGE:=/admin/ubuntu/megatron-lm/nemomegatron-lm.sqsh}"
: "${FSX_MOUNT:=/admin:/admin}"

export FI_EFA_USE_DEVICE_RDMA=1 # use for p4d
export FI_EFA_FORK_SAFE=1
export NCCL_PROTO=simple
# export NCCL_ALGO=Ring
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa
export FI_EFA_ENABLE_SHM_TRANSFER=1
# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
export NCCL_SOCKET_IFNAME=ens
export NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO
export NCCL_DEBUG_FILE=$OUT_PREFIX-nccl-debug-%h-%p.txt

# async runtime error ...
export CUDA_DEVICE_MAX_CONNECTIONS=1


declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts $FSX_MOUNT
)

declare -a TORCHRUN_ARGS=(
    --nproc_per_node=$SLURM_GPUS_PER_NODE \
    --nnodes=$SLURM_JOB_NUM_NODES \
    --rdzv_id=$SLURM_JOB_ID \
    --rdzv_backend=c10d \
    --rdzv_endpoint=$(hostname):29501 \
)

DATA_DIR=/admin/ubuntu/megatron-lm/data

srun -l "${ARGS[@]}" python -m torch.distributed.run "${TORCHRUN_ARGS[@]}" /admin/ubuntu/megatron-lm/Megatron-LM/pretrain_gpt.py \
        --tensor-model-parallel-size 8 \
        --pipeline-model-parallel-size 4 \
	--num-layers 48 \
        --hidden-size 8192 \
        --num-attention-heads 64 \
        --seq-length 2048 \
        --max-position-embeddings 2048 \
        --micro-batch-size 1 \
        --global-batch-size 288 \
        --train-samples 146484375 \
        --lr-decay-samples 126953125 \
        --lr-warmup-samples 183105 \
        --lr 6.0e-5 \
        --min-lr 6.0e-6 \
        --lr-decay-style cosine \
        --log-interval 1 \
        --eval-iters 40 \
        --eval-interval 1000 \
        --data-path "${DATA_DIR}/my-gpt2_text_document" \
        --vocab-file "${DATA_DIR}/gpt2-vocab.json" \
        --merge-file "${DATA_DIR}/gpt2-merges.txt" \
        --split 98,2,0 \
        --clip-grad 1.0 \
        --weight-decay 0.1 \
        --adam-beta1 0.9 \
        --adam-beta2 0.95 \
        --init-method-std 0.006 \
        --tensorboard-dir "${TENSORBOARD_DIR}" \
        --tensorboard-queue-size 5 \
        --log-timers-to-tensorboard \
        --log-batch-size-to-tensorboard \
        --log-validation-ppl-to-tensorboard \
        --fp16 \
        --recompute-activations

