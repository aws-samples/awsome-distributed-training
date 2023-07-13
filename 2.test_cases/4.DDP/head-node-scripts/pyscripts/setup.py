import os
import re
import ast
import yaml

#### FUNCTIONS ####
def get_channel_name_combi(channel_combi_num, channel_dict):
    name_of_channel_combi = ""
    for channel_number in iter(str(channel_combi_num)):
        name_of_channel_combi = "_".join([name_of_channel_combi, channel_dict[int(channel_number)]])
    return name_of_channel_combi

def get_channel_number_combi(channel_names, channel_dict):
    channel_combi = ""
    for channel_name in channel_names.split('_'):
        for key, value in channel_dict.items():
            if value == channel_name:
                channel_combi = "".join([channel_combi, str(key)])
    return channel_combi

def get_channel_name_combi_list(selected_channels, channel_dict):
    channel_names = []
    for channel_combi in selected_channels:
        channel_names.append(get_channel_name_combi(channel_combi,channel_dict))
    return channel_names

def save_config_file(config, save_dir):
    os.makedirs(save_dir, exist_ok=True)
    with open(f"{save_dir}/run_config_dump.json", "w") as f:
        json.dump(config, f)
    with open(f"{save_dir}/run_config_dump.yaml", "w") as f:
        yaml.dump(config, f)

def load_norm_per_channel(filepath_mean_and_std_of_dataset):
    with open(filepath_mean_and_std_of_dataset) as f:
        norm_per_channel_json = json.load(f)
        norm_per_channel = str([tuple(norm_per_channel_json['mean']), tuple(norm_per_channel_json['std'])])
        return norm_per_channel 


#### PARSING ####
name_of_run = config['meta']['name_of_run']
sk_save_dir = config['meta']['output_dir']
ViT_name = config['train_scDINO']['dino_vit_name']
epochs= int(config['train_scDINO']['epochs']+1)
save_dir_downstream_run = sk_save_dir+"/"+name_of_run
selected_channels = config['meta']['selected_channel_combination_per_run']
channel_dict = config['meta']['channel_dict']
saveckp_freq = int(config['train_scDINO']['saveckp_freq'])
epoch_nums = [epoch_num*saveckp_freq for epoch_num in range(0,(int(epochs/saveckp_freq)))]
if (epochs-1) not in epoch_nums: 
    epoch_nums.append(epochs-1)
print('Epochs for downstream analyses:', epoch_nums)
save_config_file(config, save_dir_downstream_run)

#scDINO-ViTs_path_for_extract_labels
scDINO_ViTs_for_path_extract_labels = f"{save_dir_downstream_run}/scDINO_ViTs/{ViT_name}_channel{get_channel_name_combi_list(selected_channels, channel_dict)[0]}/checkpoint0.pth"
