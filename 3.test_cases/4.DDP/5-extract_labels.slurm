#!/bin/bash

#SBATCH --wait-all-nodes=1
#SBATCH --gres=gpu:4
#SBATCH --nodes=2
#SBATCH --cpus-per-task=16
#SBATCH --ntasks-per-node=1
#SBATCH --exclusive
#SBATCH --output /apps/aws-distributed-training-workshop-pcluster/head-node-scripts/labels_out_%j.out
#SBATCH --error /apps/aws-distributed-training-workshop-pcluster/head-node-scripts/labels_err_%j.err

export WORLD_SIZE=8

nodes=( $( scontrol show hostnames $SLURM_JOB_NODELIST ) )
nodes_array=($nodes)
head_node=${nodes_array[0]}
head_node_ip=$(srun --nodes=1 --ntasks=1 -w "$head_node" hostname --ip-address)

echo Node IP: $head_node_ip
#export LOGLEVEL=INFO

# debugging flags (optional)
#export NCCL_DEBUG=INFO
#export NCCL_DEBUG_SUBSYS=ALL
#export PYTHONFAULTHANDLER=1

export LD_LIBRARY_PATH=/usr/local/lib/:$LD_LIBRARY_PATH


source /home/ec2-user/.bashrc
conda activate pytorch-py38


cd /apps/aws-distributed-training-workshop-pcluster/head-node-scripts/

nnodes=$(yq '.downstream_analyses.compute_cls_features.nnodes' scDINO_full_pipeline.yaml)
num_gpus=$(yq '.downstream_analyses.compute_cls_features.num_gpus' scDINO_full_pipeline.yaml)

epochs=$(yq '.train_scDINO.epochs' scDINO_full_pipeline.yaml)
selected_channel_indices=$(yq '.meta.selected_channel_combination_per_run' scDINO_full_pipeline.yaml) 
channel_dict=$(yq '.meta.channel_dict' scDINO_full_pipeline.yaml) 

# #Remove bracket
# selected_channel_indices_str=${selected_channel_indices//[][,.!]}

# #Remove quotes
# selected_channel_indices_str=$(sed -e 's/^"//' -e 's/"$//' <<<"$selected_channel_indices_str")


name_of_run=$(yq '.meta.name_of_run' scDINO_full_pipeline.yaml)
sk_save_dir=$(yq '.meta.output_dir' scDINO_full_pipeline.yaml)
save_dir_downstream_run=$sk_save_dir"/"$name_of_run

norm_per_channel_file=$save_dir_downstream_run"/mean_and_std_of_dataset.txt"

dino_vit_name=$(yq '.train_scDINO.dino_vit_name' scDINO_full_pipeline.yaml)
full_ViT_name=$dino_vit_name"_"$selected_channel_indices_str


path_to_model=$save_dir_downstream_run'/scDINO_ViTs/'$full_ViT_name'/checkpoint'$(($epochs-1))'.pth'

echo "Path to model: $path_to_model"


srun python -m torch.distributed.run --nnodes $nnodes\
	      --nproc_per_node $num_gpus \
	      --rdzv_id $RANDOM \
	      --rdzv_backend c10d \
	      --rdzv_endpoint $head_node_ip:29500 \
	      pyscripts/extract_image_labels.py \
	      --selected_channels $selected_channel_indices \
	      --channel_dict $channel_dict \
	      --norm_per_channel_file $norm_per_channel_file \
	      --name_of_run $name_of_run \
	      --output_dir $(yq '.meta.output_dir' scDINO_full_pipeline.yaml) \
	      --batch_size_per_gpu $(yq '.downstream_analyses.compute_cls_features.batch_size_per_gpu' scDINO_full_pipeline.yaml) \
	      --pretrained_weights $path_to_model \
	      --arch $(yq '.train_scDINO.hyperparameters.arch' scDINO_full_pipeline.yaml) \
	      --patch_size $(yq '.train_scDINO.hyperparameters.patch_size' scDINO_full_pipeline.yaml) \
	      --checkpoint_key $(yq '.downstream_analyses.compute_cls_features.checkpoint_key' scDINO_full_pipeline.yaml) \
	      --num_workers $(yq '.downstream_analyses.compute_cls_features.num_workers' scDINO_full_pipeline.yaml) \
	      --dist_url $(yq '.train_scDINO.dist_url' scDINO_full_pipeline.yaml) \
	      --dataset_dir $(yq '.meta.dataset_dir' scDINO_full_pipeline.yaml) \
	      --resize 'True'\
	      --resize_length $(yq '.downstream_analyses.compute_cls_features.resize_length' scDINO_full_pipeline.yaml) \
	      --center_crop $(yq '.meta.center_crop' scDINO_full_pipeline.yaml) \
	      --normalize 'True'\
	      --full_ViT_name $full_ViT_name \
	      --train_datasetsplit_fraction $(yq '.meta.train_datasetsplit_fraction' scDINO_full_pipeline.yaml) \
	      --seed $(yq '.meta.seed' scDINO_full_pipeline.yaml) \
	      --folder_depth_for_labels $(yq '.meta.folder_depth_for_labels' scDINO_full_pipeline.yaml)



	      

