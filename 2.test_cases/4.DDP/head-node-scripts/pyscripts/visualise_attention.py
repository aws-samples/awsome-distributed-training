import argparse
import utils
from tifffile import imread
import numpy as np
import ast
import torch
from torchvision import transforms, datasets
import os
from torchvision import models as torchvision_models
from torch import nn
import re
import sys
import cv2
import random
import colorsys
import skimage.io
from skimage.measure import find_contours
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon
import torch.nn as nn
import torchvision
import vision_transformer as vits
import numpy as np
import json


def apply_mask(image, mask, color, alpha=0.5):
    for c in range(3):
        image[:, :, c] = image[:, :, c] * (1 - alpha * mask) + alpha * mask * color[c] * 255
    return image


def random_colors(N, bright=True):
    """
    Generate random colors.
    """
    brightness = 1.0 if bright else 0.7
    hsv = [(i / N, 1, brightness) for i in range(N)]
    colors = list(map(lambda c: colorsys.hsv_to_rgb(*c), hsv))
    random.shuffle(colors)
    return colors


def display_instances(image, mask, fname="test", figsize=(5, 5), blur=False, contour=True, alpha=0.5):
    fig = plt.figure(figsize=figsize, frameon=False)
    ax = plt.Axes(fig, [0., 0., 1., 1.])
    ax.set_axis_off()
    fig.add_axes(ax)
    ax = plt.gca()

    N = 1
    mask = mask[None, :, :]
    # Generate random colors
    colors = random_colors(N)

    # Show area outside image boundaries.
    height, width = image.shape[:2]
    margin = 0
    ax.set_ylim(height + margin, -margin)
    ax.set_xlim(-margin, width + margin)
    ax.axis('off')
    masked_image = image.astype(np.uint32).copy()
    for i in range(N):
        color = colors[i]
        _mask = mask[i]
        if blur:
            _mask = cv2.blur(_mask,(10,10))
        # Mask
        masked_image = apply_mask(masked_image, _mask, color, alpha)
        # Mask Polygon
        # Pad to ensure proper polygons for masks that touch image edges.
        if contour:
            padded_mask = np.zeros((_mask.shape[0] + 2, _mask.shape[1] + 2))
            padded_mask[1:-1, 1:-1] = _mask
            contours = find_contours(padded_mask, 0.5)
            for verts in contours:
                # Subtract the padding and flip (y, x) to (x, y)
                verts = np.fliplr(verts) - 1
                p = Polygon(verts, facecolor="none", edgecolor=color)
                ax.add_patch(p)
    ax.imshow(masked_image.astype(np.uint8), aspect='auto')
    fig.savefig(fname)
    return


if __name__ == '__main__':
    parser = argparse.ArgumentParser('Visualize Self-Attention maps')
    parser.add_argument('--arch', default='vit_small', type=str, help='Architecture')
    parser.add_argument('--patch_size', default=8, type=int, help='Patch resolution of the model.')
    parser.add_argument('--pretrained_weights', default='', type=str,
        help="Path to pretrained weights to load.")
    parser.add_argument("--checkpoint_key", default="teacher", type=str,
        help='Key to use in the checkpoint (example: "teacher")')
    parser.add_argument('--resize_attention_image',type=str, default=True, help="Wheter to resize image or not")
    parser.add_argument("--image_size", default=(480, 480), type=int, nargs="+", help="Resize image.")
    parser.add_argument("--threshold", type=float, default=None, help="""We visualize masks
        obtained by thresholding the self-attention maps to keep xx% of the mass.""")
    parser.add_argument('--output_dir', default='.', type=str)    
    parser.add_argument('--dataset_dir', default='/path/to/imagenet/', type=str)
    parser.add_argument ('--images_are_RGB',help='If images are RGB, set this to True. If images are grayscale, set this to False.', default=False, type=utils.bool_flag)
    parser.add_argument('--selected_channels', default=[0,1,2], nargs='+', help="""list of channel indexes of the .tiff images which should be used to create the tensors.""")
    parser.add_argument('--channel_dict', default=None, type=str,help="""name of the channels in format as dict channel_number, channel_name.""")
    parser.add_argument('--resize', default=False, help="""if images should be resized""")
    parser.add_argument('--resize_length', default=None, help="""quadratic resize length to resize images""")
    parser.add_argument('--norm_per_channel', default="[(x, x, x, x, x), (x, x, x, x, x)]", type=str, help="""2x tuple of mean and std per channel typically values between 0 and 1""")
    parser.add_argument('--norm_per_channel_file', default=None, help="""path to file with mean and std per channel in json format.""")
    parser.add_argument('--center_crop', default=None, help="""center crop factor to crop images""")
    parser.add_argument('--normalize', default="False", type=str, help="""normalize with mean and std per channel""")
    parser.add_argument('--patch_embedding_mapping', default=None, help="""change the patch embedding weights by inputting a string of the sequence of rearrangement of the model '[0,1,2]' or the string 'average_weights' or None""")
    parser.add_argument('--parse_params',help='Load settings from file in json format. Command line options override values in file.')
    parser.add_argument('--use_weighted_sampler', default=False, type=bool, help='Use weighted sampler for training.')
    parser.add_argument("--num_images", default=None, type=int, help="Number of images to run in total.")
    parser.add_argument("--read_model_arch_dynamically", default=None, type=str, help="Read model architecture from pretrained weights")
    parser.add_argument("--use_mean_patch_embedding", default=False, type=bool, help="Use mean patch embedding instead of first patch embedding")
    parser.add_argument("--use_custom_embedding_map", default=False, type=bool, help="Use custom embedding map")
    parser.add_argument("--custom_embedding_map", default=None, type=dict, help="Custom embedding map")
    parser.add_argument("--name_of_run", default=False, type=bool, help="Name of job")
    parser.add_argument("--num_per_class", default=False, type=bool, help="Use custom embedding map")
    parser.add_argument("--scDINO_full_pipeline", default=False, type=bool, help="Using scDINO full pipeline")
    parser.add_argument('--full_ViT_name', default='full_vit_name', type=str, help='name channel combi ViT')
    parser.add_argument('--seed', default=42, type=int, help='Random seed.')

    #save settings
    args = parser.parse_args()

    args.selected_channels = list(map(int, args.selected_channels[0].split(',')))
    args.channel_dict = dict(zip(args.selected_channels, args.channel_dict.split(',')))

    if args.parse_params:
        t_args = argparse.Namespace()
        t_args.__dict__.update(ast.literal_eval(args.parse_params))
        args = parser.parse_args(namespace=t_args)

    # read mean and std per channel
    if args.norm_per_channel_file:
        with open(args.norm_per_channel_file) as f:
            norm_per_channel_json = json.load(f)
            norm_per_channel = str([tuple(norm_per_channel_json['mean']), tuple(norm_per_channel_json['std'])])
            args.norm_per_channel = norm_per_channel

    print("\n".join("%s: %s" % (k, str(v)) for k, v in sorted(dict(vars(args)).items())))

#adjust model arch and patch size according to pretrained weights
def adjust_model_architecture(args):
    model_name = args.pretrained_weights.split("/")[-1]
    number = re.findall(r'\d+', model_name)
    if number:
        args.patch_size = int(number[0])
    if "small" in model_name:
        args.arch = "vit_small"
    elif "base" in model_name:
        args.arch = "vit_base"

if args.read_model_arch_dynamically:
    adjust_model_architecture(args)

# ============ building network ... ============
# build model
device = torch.device("cpu")
selected_channels = list(map(int, args.selected_channels))
num_in_chans_pretrained = utils.get_pretrained_weights_in_chans(args.pretrained_weights)
model = vits.__dict__[args.arch](patch_size=args.patch_size, num_classes=0, in_chans=num_in_chans_pretrained)
for p in model.parameters():
    p.requires_grad = False
model.eval()
model.to(device)
print('device:', device)
if os.path.isfile(args.pretrained_weights):
    state_dict = torch.load(args.pretrained_weights, map_location="cpu")
    if args.checkpoint_key is not None and args.checkpoint_key in state_dict:
        print(f"Take key {args.checkpoint_key} in provided checkpoint dict")
        state_dict = state_dict[args.checkpoint_key]
    # remove `module.` prefix
    state_dict = {k.replace("module.", ""): v for k, v in state_dict.items()}
    # remove `backbone.` prefix induced by multicrop wrapper
    state_dict = {k.replace("backbone.", ""): v for k, v in state_dict.items()}
    msg = model.load_state_dict(state_dict, strict=False)
    print('Pretrained weights found at {} and loaded with msg: {}'.format(args.pretrained_weights, msg))
else:
    print("Please use the `--pretrained_weights` argument to indicate the path of the checkpoint to evaluate.")

# ============ adjusting ViT model option... ============

def embedding_seq(custom_embedding_map, selected_channels):
        map_dict = ast.literal_eval(custom_embedding_map)
        map_dict = {int(k):int(v) for k,v in map_dict.items()}
        embedding_seq = [map_dict[int(input_channel)] for input_channel in selected_channels]
        return embedding_seq

def build_weight_emb(embedding_seq, model):
    weights = model.patch_embed.proj.weight
    weights = weights[:,embedding_seq,:,:]
    model.patch_embed.proj.weight = nn.Parameter(weights)
    return model

if not args.use_mean_patch_embedding and not args.use_custom_embedding_map:
    if len(selected_channels) != num_in_chans_pretrained:
        print(f"Error: Number of channels in the dataset ({len(selected_channels)}) and pretrained weights ({num_in_chans_pretrained}) are different")
        print(f"Use --use_mean_patch_embedding or --use_custom_embedding_map to adjust the number of channels")
        sys.exit(1)

if not args.images_are_RGB:
    if args.use_mean_patch_embedding:
        average_conv2d_weights = torch.mean(model.patch_embed.proj.weight,1, keepdim=True)
        conv2d_weights_per_chan = average_conv2d_weights.repeat(1,len(selected_channels),1,1)
        model.patch_embed.proj.weight = nn.Parameter(conv2d_weights_per_chan)
    elif args.use_custom_embedding_map:
        embedding_seq = embedding_seq(args.custom_embedding_map, args.selected_channels)
        model = build_weight_emb(embedding_seq, model)

def prepare_img(image, args):
    if not args.images_are_RGB:
        image = utils.normalize_numpy_0_to_1(image)
        image = torch.from_numpy(image).permute(2, 0, 1)
        img = image.type(torch.FloatTensor)
        transform = transforms.Compose([])
        if args.center_crop:
            transform.transforms.append(transforms.CenterCrop(args.center_crop))
        if args.resize:
            transform.transforms.append(transforms.Resize(args.resize_length))
        if args.normalize:
            selected_channels = list(map(int, args.selected_channels))
            norm_per_channel = ast.literal_eval(args.norm_per_channel)
            mean_for_selected_channel, std_for_selected_channel = tuple([norm_per_channel[0][mean] for mean in selected_channels]), tuple([norm_per_channel[1][mean] for mean in selected_channels])
            transform.transforms.append(transforms.Normalize(mean=mean_for_selected_channel, std=std_for_selected_channel))
        img = transform(img)
    else:
        transform = transforms.Compose([
        transforms.Resize(256, interpolation=3),
        transforms.CenterCrop(224),
        transforms.ToTensor(),
        transforms.Normalize((0.485, 0.456, 0.406), (0.229, 0.224, 0.225)),
        ])
        img = transform(img)
    return img

def prepare_og_image(image, args, channel):
    image = utils.normalize_numpy_0_to_1(image)
    image = torch.from_numpy(image).permute(2, 0, 1)
    img = image.type(torch.FloatTensor)
    transform = transforms.Compose([])
    if args.center_crop:
        transform.transforms.append(transforms.CenterCrop(args.center_crop))
    if args.resize:
        transform.transforms.append(transforms.Resize(args.resize_length))
    if args.normalize:
        selected_channels = [channel for i in range(3)]
        norm_per_channel = ast.literal_eval(args.norm_per_channel)
        mean_for_selected_channel, std_for_selected_channel = tuple([norm_per_channel[0][mean] for mean in selected_channels]), tuple([norm_per_channel[1][mean] for mean in selected_channels])
        transform.transforms.append(transforms.Normalize(mean=mean_for_selected_channel, std=std_for_selected_channel))
    img = transform(img)
    return img

dataset_total =  datasets.ImageFolder(os.path.join(args.dataset_dir))

classes = utils.fetch_all_folder_names_of_folder_depth(dataset_total, folder_depth=args.folder_depth_for_labels)

def get_channel_name_combi(channel_combi, channel_dict):
            name_of_channel_combi = ""
            for channel_number in iter(str(channel_combi)):
                name_of_channel_combi = "_".join([name_of_channel_combi, channel_dict[int(channel_number)]])
            return name_of_channel_combi

selected_channel_str = "".join(str(x) for x in args.selected_channels)
channel_names = get_channel_name_combi(selected_channel_str, args.channel_dict)

#create directory for attention images
if args.scDINO_full_pipeline:
    checkpoint = args.pretrained_weights.split('/')[-1]
    epoch_num = re.findall(r'\d+', checkpoint)[0]
    run_directory = os.path.join(args.output_dir,args.name_of_run, f"{args.full_ViT_name}_analyses/attention_images/epoch{epoch_num}")
else:
    checkpoint = args.pretrained_weights.split('/')[-1].split('.')[0]
    run_directory = os.path.join(args.output_dir,args.name_of_run, f"attention_images/channel{channel_names}_model_{checkpoint}")
try:
    os.mkdir(run_directory)
except:
    pass
for class_name in classes:
    try:
        os.mkdir(f"{run_directory}/{class_name}")
    except:
        pass

# classes_dict = dataset_total.class_to_idx
# random.seed(args.seed)

# classes_dict = {class_name: i for i, class_name in enumerate(classes)}

print('Computing and saving attention images...')
for class_name in classes:
# for class_name, class_number in classes_dict.items():
    # class_torch = torch.tensor([class_number])
    class_indices = [i for i, x in enumerate(dataset_total.imgs) if class_name == x[0].split('/')[-args.folder_depth_for_labels-2]]
    print(f"Computing attention images for class {class_name} with {len(class_indices)} images")
    print(class_indices)
    if args.scDINO_full_pipeline: #subsample from val_indices
        validation_split = float(1-args.train_datasetsplit_fraction)
        shuffle_dataset = True
        # Creating data indices for training and validation splits:
        dataset_size = len(dataset_total)
        indices = list(range(dataset_size))
        split = int(np.floor(validation_split * dataset_size))
        if shuffle_dataset :
            np.random.seed(args.seed)
            np.random.shuffle(indices)
        train_indices, val_indices = indices[split:], indices[:split]
        val_indices_intersect = list(set(val_indices) & set(list(map(int, class_indices))))
        random_indices = random.sample(val_indices_intersect, args.num_images_per_class)
    else: #sample from whole dataset
        random_indices = random.sample(list(class_indices), args.num_images_per_class)
    for cell in random_indices:
        image_path = dataset_total.samples[cell][0]
        cell_name = image_path.split('/')[-1]
        random_cell_dir= f"{run_directory}/{class_name}/{cell_name}"
        try:
            os.mkdir(random_cell_dir)
        except:
            pass
        image_raw = imread(image_path)
        image_raw=image_raw.astype(float)
        image = image_raw[:,:,selected_channels]
        img = prepare_img(image, args)

        images_to_visualise = []
        images_to_visualise.append(img)

        if args.resize_attention_image:
            resize= torchvision.transforms.Resize((args.image_size))
            img_resized = resize(img)
            images_to_visualise.append(img_resized)
        
        #save original images
        for channel in selected_channels:
            channel_name = get_channel_name_combi(str(channel), args.channel_dict)
            multiplied_channels = [channel for i in range(3)]
            image = image_raw[:,:,multiplied_channels]
            og_img= prepare_og_image(image, args, channel)
            torchvision.utils.save_image(torchvision.utils.make_grid(og_img, normalize=True, scale_each=True), os.path.join(f"{random_cell_dir}/original_img_channel"+str(channel_name)+".png"))

        for img in images_to_visualise:
            # make the image divisible by the patch size
            w, h = img.shape[1] - img.shape[1] % args.patch_size, img.shape[2] - img.shape[2] % args.patch_size
            img = img[:, :w, :h].unsqueeze(0)

            w_featmap = img.shape[-2] // args.patch_size
            h_featmap = img.shape[-1] // args.patch_size

            try:
                attentions = model.get_last_selfattention(img.to(device))
            ## print the erorr message
            except Exception as e:
                print("Error in getting attention images for image.shape: ", img.shape)
                print(e)
                continue

            nh = attentions.shape[1] # number of head

            # we keep only the output patch attention
            attentions = attentions[0, :, 0, 1:].reshape(nh, -1)

            if args.threshold is not None:
                # we keep only a certain percentage of the mass
                val, idx = torch.sort(attentions)
                val /= torch.sum(val, dim=1, keepdim=True)
                cumval = torch.cumsum(val, dim=1)
                th_attn = cumval > (1 - args.threshold)
                idx2 = torch.argsort(idx)
                for head in range(nh):
                    th_attn[head] = th_attn[head][idx2[head]]
                th_attn = th_attn.reshape(nh, w_featmap, h_featmap).float()
                # interpolate
                th_attn = nn.functional.interpolate(th_attn.unsqueeze(0), scale_factor=args.patch_size, mode="nearest")[0].cpu().detach().numpy()

            attentions = attentions.reshape(nh, w_featmap, h_featmap)
            attentions = nn.functional.interpolate(attentions.unsqueeze(0), scale_factor=args.patch_size, mode="nearest")[0].cpu().detach().numpy()
            
            image_size = img.shape[-1]
            try:
                final_dir = f"{random_cell_dir}/image_size_{image_size}"
                os.mkdir(final_dir)
            except:
                pass

            for j in range(nh):
                fname = os.path.join(final_dir, "attn-head" + str(j)+".png")
                plt.imsave(fname=fname, arr=attentions[j], format='png')
                

            if args.threshold is not None:
                image = skimage.io.imread(os.path.join(random_cell_dir,".png"))
        
                for j in range(nh):
                    display_instances(image, th_attn[j], fname=os.path.join(random_cell_dir, "mask_th" + str(args.threshold) + "_head" + str(j)+".png"), blur=False)
            #free gpu memory
            del img
            del attentions
    
#creating log file
with open(os.path.join(run_directory, "run_log.txt"), "w") as f:
    f.write(f"successfully computed attention visualisation with following parameters and random seed {args.seed}: \n")
    f.write("parameters: \n")
    for arg in vars(args):
        f.write(f"{arg} : {getattr(args, arg)} \n")