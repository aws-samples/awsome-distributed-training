import argparse
import utils
from tifffile import imread
import numpy as np
import torch.backends.cudnn as cudnn
import ast
import torch
from torchvision import transforms, datasets
import os
from catalyst.data import DistributedSamplerWrapper
import sys
import vision_transformer as vits
from torchvision import models as torchvision_models
from torch import nn
import torch.distributed as dist
import re
import json


def extract_and_save_feature_pipeline(args):
    # ============ preparing image data ... ============

    torch.manual_seed(args.seed)
    
    if not args.images_are_RGB:
        #image loader compatible with multi-channel images
        #prepare selected channels and their corresponding mean and std
        selected_channels = list(map(int, args.selected_channels))
        transform = transforms.Compose([])
        if args.resize:
            transform.transforms.append(transforms.Resize(args.resize_length))
        if args.normalize:
            norm_per_channel = ast.literal_eval(args.norm_per_channel)
            mean_for_selected_channel, std_for_selected_channel = tuple([norm_per_channel[0][mean] for mean in selected_channels]), tuple([norm_per_channel[1][mean] for mean in selected_channels])
            print("normalize with mean: ", mean_for_selected_channel, " and std: ", std_for_selected_channel)
            transform.transforms.append(transforms.Normalize(mean=mean_for_selected_channel, std=std_for_selected_channel))

        def load_image(self, idx, args):
            path, target = self.samples[idx]
            image = imread(path)
            image = image[:, :, selected_channels]
            image = image.astype(float)
            if args.center_crop:
                image = torch.from_numpy(image).permute(2, 0, 1)
                transform = transforms.CenterCrop(args.center_crop)
                image = transform(image)
                image = image.permute(1, 2, 0)
                image = image.numpy()
            return image

        class Multichannel_dataset(datasets.ImageFolder):
                def __getitem__(self, idx):
                    path, target = self.samples[idx]
                    image_np = load_image(self, idx, args)
                    image_np = utils.normalize_numpy_0_to_1(image_np)
                    if utils.check_nan(image_np):
                        print("nan in image: ", path)
                        print('taking first image in dataset as replacement, so there are duplicates instead of nan values')
                        image_np = load_image(self, 0, args)
                        image_np = utils.normalize_numpy_0_to_1(image_np)
                    image = torch.from_numpy(image_np).permute(2, 0, 1)
                    if self.transform is not None:
                        image = self.transform(image)
                    if torch.isnan(image).any():
                        print("nan in image")
                    return image, idx
    
        dataset_total =  Multichannel_dataset(os.path.join(args.dataset_dir), transform=transform)
    
    else: #images are RGB
        transform = transforms.Compose([
        transforms.Resize(256, interpolation=3),
        transforms.CenterCrop(224),
        transforms.ToTensor(),
        transforms.Normalize((0.485, 0.456, 0.406), (0.229, 0.224, 0.225)),
        ])

        class ReturnIndexDataset(datasets.ImageFolder):
            def __getitem__(self, idx):
                img, lab = super(ReturnIndexDataset, self).__getitem__(idx)
                return img, idx
        dataset_total = ReturnIndexDataset(os.path.join(args.dataset_dir), transform=transform)

    # SAMPLER SECTION
    if  args.use_weighted_sampler and args.class_weights and args.num_samples:
            print('Using weighted sampler')
            num_samples = args.num_samples
            weights_per_class = ast.literal_eval(args.class_weights)
            weights_per_sample = [weights_per_class[dataset_total.samples[i][1]] for i in range(len(dataset_total.samples))]
            weighted_sampler = torch.utils.data.sampler.WeightedRandomSampler(weights_per_sample, args.num_samples, replacement=False)
            sampler = DistributedSamplerWrapper(weighted_sampler)
    
    elif args.scDINO_full_pipeline:
        validation_split = float(1-args.train_datasetsplit_fraction)
        shuffle_dataset = True
        dataset_size = len(dataset_total)
        indices = list(range(dataset_size))
        split = int(np.floor(validation_split * dataset_size))
        if shuffle_dataset :
            np.random.seed(args.seed)
            np.random.shuffle(indices)
        train_indices, val_indices = indices[split:], indices[:split]
        val_sampler = torch.utils.data.SubsetRandomSampler(val_indices)
        sampler = DistributedSamplerWrapper(val_sampler)
        num_samples = len(val_indices)
    
    elif args.test_datasetsplit_fraction!=1:
        validation_split = float(args.test_datasetsplit_fraction)
        shuffle_dataset = True
        dataset_size = len(dataset_total)
        indices = list(range(dataset_size))
        split = int(np.floor(validation_split * dataset_size))
        if shuffle_dataset :
            np.random.seed(args.seed)
            np.random.shuffle(indices)
        train_indices, val_indices = indices[split:], indices[:split]
        val_sampler = torch.utils.data.SubsetRandomSampler(val_indices)
        sampler = DistributedSamplerWrapper(val_sampler)
        num_samples = len(val_indices)

    else:
        print("Loading all images of the dataset")
        sampler = torch.utils.data.DistributedSampler(dataset_total, shuffle=False)
        num_samples = len(dataset_total)

    data_loader = torch.utils.data.DataLoader(
        dataset_total,
        sampler=sampler,
        batch_size=args.batch_size_per_gpu,
        num_workers=args.num_workers,
        pin_memory=True,
        drop_last=False,
        shuffle=False)
    
    print("Data loader created")

    local_batch, local_lables = next(iter(data_loader))
    num_channels=local_batch.shape[1]

    print(f"Data loaded with {num_samples} images with a size of {local_batch.shape[2]}x{local_batch.shape[3]} with {num_channels} channels")

    # ============ building network ... ============
    if "vit" in args.arch:
        num_in_chans_pretrained = utils.get_pretrained_weights_in_chans(args.pretrained_weights)
        print(f"Pretrained weights have {num_in_chans_pretrained} input channels")
        model = vits.__dict__[args.arch](patch_size=args.patch_size, num_classes=0, in_chans=int(num_in_chans_pretrained))
        model.cuda()
        utils.load_pretrained_weights(model, args.pretrained_weights, args.checkpoint_key, args.arch, args.patch_size)
        model.eval()
        print(f"Model {args.arch} {args.patch_size}x{args.patch_size} with {num_in_chans_pretrained} in_chans built.")
    else:
        print(f"Architecture {args.arch} non supported")
        sys.exit(1)


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
        if num_channels != num_in_chans_pretrained:
            print(f"Error: Number of channels in the dataset ({num_channels}) and pretrained weights ({num_in_chans_pretrained}) are different")
            print(f"Use --use_mean_patch_embedding or --use_custom_embedding_map to adjust the number of channels")
            raise ValueError(f"Number of channels in the dataset ({num_channels}) and pretrained weights ({num_in_chans_pretrained}) are different")

    if not args.images_are_RGB:
        if args.use_mean_patch_embedding:
            average_conv2d_weights = torch.mean(model.patch_embed.proj.weight,1, keepdim=True)
            conv2d_weights_per_chan = average_conv2d_weights.repeat(1,num_channels,1,1)
            model.patch_embed.proj.weight = nn.Parameter(conv2d_weights_per_chan)
        elif args.use_custom_embedding_map:
            embedding_seq = embedding_seq(args.custom_embedding_map, args.selected_channels)
            model = build_weight_emb(embedding_seq, model)

    # ============ extract features ... ============
    print("Extracting features for train set...")
    features, index_all = extract_features(model, data_loader, args.use_cuda)

    if utils.get_rank() == 0:
        features = nn.functional.normalize(features, dim=1, p=2)
    
    image_names= [dataset_total.samples[i][0] for i in index_all]
    labels = [utils.fetch_foldername_of_img_location(dataset_total,i, args.folder_depth_for_labels) for i in index_all]
    return features, labels, image_names

@torch.no_grad()
def extract_features(model, data_loader, use_cuda=True, multiscale=False):
    metric_logger = utils.MetricLogger(delimiter="  ")
    features = None
    indices_all = []
    for samples, index in metric_logger.log_every(data_loader, 10):
        samples = samples.cuda(non_blocking=True)
        index = index.cuda(non_blocking=True)
        if multiscale:
            feats = utils.multi_scale(samples, model)
        else:
            feats = model(samples.float()).clone()

        # init storage feature matrix
        if dist.get_rank() == 0 and features is None:
            features = torch.zeros(0, feats.shape[-1])
            if use_cuda:
                features = features.cuda(non_blocking=True)
            print(f"Storing features into tensor of shape {features.shape}")

        # get indexes from all processes
        y_all = torch.empty(dist.get_world_size(), index.size(0), dtype=index.dtype, device=index.device)
        y_l = list(y_all.unbind(0))
        y_all_reduce = torch.distributed.all_gather(y_l, index, async_op=True)
        y_all_reduce.wait()
        index_all = torch.cat(y_l)

        # share features between processes
        feats_all = torch.empty(
            dist.get_world_size(),
            feats.size(0),
            feats.size(1),
            dtype=feats.dtype,
            device=feats.device,
        )
        output_l = list(feats_all.unbind(0))
        output_all_reduce = torch.distributed.all_gather(output_l, feats, async_op=True)
        output_all_reduce.wait()

        # update storage feature matrix
        if dist.get_rank() == 0:
            if use_cuda:
                features = torch.cat((features,torch.cat(output_l)),0)
                indices_all.extend(index_all.tolist())
            else:
                features = torch.cat((features.cpu(),torch.cat(output_l).cpu()),0)
                indices_all.extend(index_all.tolist())
    return features, indices_all

if __name__ == '__main__':
    parser = argparse.ArgumentParser('Computation of CLS features')
    #computation settings
    parser.add_argument('--name_of_run', default='/recent_run', type=str)
    parser.add_argument('--batch_size_per_gpu', default=30, type=int, help='Per-GPU batch-size')
    parser.add_argument('--pretrained_weights', default='', type=str, help="Path to pretrained weights to evaluate.")
    parser.add_argument('--use_cuda', default=True, type=utils.bool_flag,
        help="Should we store the features on GPU? We recommend setting this to False if you encounter OOM")
    parser.add_argument('--arch', default='vit_small', type=str, help='Architecture')
    parser.add_argument('--patch_size', default=16, type=int, help='Patch resolution of the model.')
    parser.add_argument("--checkpoint_key", default="teacher", type=str,
        help='Key to use in the checkpoint (example: "teacher")')
    parser.add_argument('--num_workers', default=0, type=int, help='Number of data loading workers per GPU.')
    parser.add_argument("--dist_url", default="env://", type=str, help="""url used to set up
        distributed training; see https://pytorch.org/docs/stable/distributed.html""")
    parser.add_argument("--local_rank", default=0, type=int, help="Please ignore and do not set this argument.")
    #image dataset settings
    parser.add_argument('--dataset_dir', default='/path/to/imagenet/', type=str)
    parser.add_argument ('--images_are_RGB',help='If images are RGB, set this to True. If images are grayscale, set this to False.', default=False, type=utils.bool_flag)
    parser.add_argument('--selected_channels', default=[0,1,2], nargs='+', help="""list of channel indexes of the .tiff images which should be used to create the tensors.""")
    parser.add_argument('--channel_dict', default=None, type=str,help="""name of the channels in format as dict channel_number, channel_name.""")
    parser.add_argument('--resize', default=False, help="""if images should be resized""")
    parser.add_argument('--resize_length', default=None, help="""quadratic resize length to resize images""")
    parser.add_argument('--norm_per_channel', default="[(x, x, x, x, x), (x, x, x, x, x)]", type=str, help="""2x tuple of mean and std per channel typically values between 0 and 1""")
    parser.add_argument('--norm_per_channel_file', default=None, help="""path to file with mean and std per channel in json format.""")
    parser.add_argument('--center_crop', type=int, default=None, help="""center crop factor to crop images""")
    parser.add_argument('--normalize', default="False", type=str, help="""normalize with mean and std per channel""")
    parser.add_argument('--patch_embedding_mapping', default=None, help="""change the patch embedding weights by inputting a string of the sequence of rearrangement of the model '[0,1,2]' or the string 'average_weights' or None""")
    parser.add_argument('--parse_params',help='Load settings from file in json format. Command line options override values in file.')
    parser.add_argument('--use_weighted_sampler', default=False, type=bool, help='Use weighted sampler for training.')
    parser.add_argument('--class_weights', default=None, help="""list of weights for each class""")
    parser.add_argument("--num_samples", default=None, type=int, help="Number of images to run in total.")
    parser.add_argument("--read_model_arch_dynamically", default=None, type=str, help="Read model architecture from pretrained weights")
    parser.add_argument("--use_mean_patch_embedding", default=False, type=bool, help="Use mean patch embedding instead of first patch embedding")
    parser.add_argument("--use_custom_embedding_map", default=False, type=bool, help="Use custom embedding map")
    parser.add_argument("--custom_embedding_map", default=None, type=dict, help="Custom embedding map")
    parser.add_argument("--scDINO_full_pipeline", default=False, type=bool, help="Using scDINO full pipeline")
    parser.add_argument('--full_ViT_name', default='full_vit_name', type=str, help='name channel combi ViT')
    parser.add_argument("--train_datasetsplit_fraction", default=0.8, type=float, help="when using scDINO full pipeline")
    parser.add_argument("--test_datasetsplit_fraction", default=0.8, type=float, help="when using downstream analysis only")
    parser.add_argument('--seed', default=42, type=int, help='Random seed.')
    parser.add_argument('--folder_depth_for_labels', default=0, type=int, help='Folder depth for labels. 0 means that the labels are the folder names where the images are stored. 1 means one level above and so on. e.g  path/to/images/labelwhen3/labelwhen2/labelwhen1/labelwhen0/image.tiff')

    #save settings
    parser.add_argument('--output_dir', default='.', type=str)
    args = parser.parse_args()

    args.selected_channels = list(map(int, args.selected_channels[0].split(',')))
    args.channel_dict = dict(zip(args.selected_channels, args.channel_dict.split(',')))
    args.resize_length = (int(args.resize_length),int(args.resize_length))

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

    utils.init_distributed_mode(args)
    print("git:\n  {}\n".format(utils.get_sha()))
    print("\n".join("%s: %s" % (k, str(v)) for k, v in sorted(dict(vars(args)).items())))
    cudnn.benchmark = True

    #compute CLS features and save them
    features, labels, image_names = extract_and_save_feature_pipeline(args)
    # save features and labels as files
    if dist.get_rank() == 0:

        #translate channel indexes to channel names
        def get_channel_name_combi(channel_combi, channel_dict):
            name_of_channel_combi = ""
            for channel_number in iter(str(channel_combi)):
                name_of_channel_combi = "_".join([name_of_channel_combi, channel_dict[int(channel_number)]])
            return name_of_channel_combi

        #concatenate args.selected_channels to string
        selected_channel_str = "".join(str(x) for x in args.selected_channels)
        channel_names = get_channel_name_combi(selected_channel_str, args.channel_dict)

        if args.scDINO_full_pipeline:
            path = os.path.join(args.output_dir,args.name_of_run)+"/"
          
        else: 
             path = os.path.join(args.output_dir,args.name_of_run, f"CLS_features/")
            
        np.savetxt(f"{path}class_labels.csv", labels, delimiter=",", fmt="%s")
        np.savetxt(f"{path}image_paths.csv", image_names, delimiter=",", fmt="%s")
