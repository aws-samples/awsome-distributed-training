import torch
from torch.utils.data import DataLoader
from tqdm import tqdm
from torch.nn import functional as F
import torch_xla.core.xla_model as xm
# XLA imports for parallel loader and multi-processing
import torch_xla.distributed.parallel_loader as pl

from mingpt.model import GPT
from mingpt.datasets import SortDataset 
from mingpt.trainer import Trainer
from mingpt.configs import TrainConfig

import os
#os.environ['NEURON_CC_FLAGS'] = "--log_level=INFO"
#os.environ["NEURON_USE_EAGER_DEBUG_MODE"] = "1"
#os.environ["NEURON_FRAMEWORK_DEBUG"] = "1"
#os.environ["NEURON_RT_LOG_LEVEL"]="DEBUG"
#os.environ["NEURON_RT_LOG_LEVEL_NRT"]="DEBUG"
#os.environ["NEURON_DUMP_HLO_SNAPSHOT"] = "1"


device = 'xla'
# create train and test dataset
train_dataset = SortDataset('train')
test_dataset = SortDataset('test')
train_config = TrainConfig.get_default_config()
train_loader = DataLoader(
    train_dataset,
    batch_size=train_config.batch_size,
    )
# We wrap the dataloader with MpDeviceLoader. This dataloader should take
# care of copying the tensors to device
train_loader = pl.MpDeviceLoader(train_loader, device)

# create a GPT instance
model_config = GPT.get_default_config()
model_config.model_type = 'gpt-nano'
model_config.vocab_size = train_dataset.get_vocab_size()
model_config.block_size = train_dataset.get_block_size()
model = GPT(model_config)
model = model.to(device)
optimizer = model.configure_optimizers(train_config)


model.train()
pbar = tqdm(enumerate(train_loader))
for idx, (x, y) in pbar:
    optimizer.zero_grad()
    # forward the model
    logits = model(x)
    loss = F.cross_entropy(
        logits.view(-1, logits.size(-1)),
        y.view(-1),
        ignore_index=-1
    )
    # backprop and update the parameters
    #model.zero_grad(set_to_none=True)
    loss.backward()
    xm.optimizer_step(optimizer) # XLA MP: performs grad allreduce and optimizer step
    #torch.nn.utils.clip_grad_norm_(model.parameters(), train_config.grad_norm_clip)
    #pbar.set_description(f"Iteration: {idx}, train loss: {loss.item():.5f}")
    pbar.set_description(f"Iteration: {idx}") #, train loss: {loss.item():.5f}")
    if idx == 500:
        break
