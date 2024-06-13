import os
import torch
from torch.utils.data import DataLoader
from tqdm import tqdm
import torch.nn.functional as F
import torch_xla.core.xla_model as xm
# XLA imports for parallel loader and multi-processing
import torch_xla.distributed.parallel_loader as pl
from torch_xla.distributed.zero_redundancy_optimizer import ZeroRedundancyOptimizer


from olmo.config import ModelConfig, TrainConfig, TokenizerConfig
from olmo.datasets import SortDataset
from olmo.model import OLMo
from olmo.tokenizer import Tokenizer

# Set Neuron SDK environment variables
os.environ["XLA_USE_BF16"] = "1"


device = "xla"
olmo_config = TrainConfig.load("./configs/OLMo-7B.yaml")
olmo_config.model.init_device = "cpu"
#tokenizer = Tokenizer.from_train_config(olmo_config)
model = OLMo(olmo_config.model)
model = model.to(device)
print("Loaded olmo model")
# Define the batch size and sequence length
batch_size = 4
# create train and test dataset
train_dataset = SortDataset('train')
test_dataset = SortDataset('test')
train_loader = DataLoader(
    train_dataset,
    batch_size=batch_size,
)
# We wrap the dataloader with MpDeviceLoader. This dataloader should take
# care of copying the tensors to device
train_loader = pl.MpDeviceLoader(train_loader, device)
optimizer = torch.optim.Adam(model.parameters(), lr=1e-4)
model.train()

pbar = tqdm(train_loader)
for idx, (x, y) in enumerate(pbar):
    optimizer.zero_grad()
    # forward the model
    logits = model(x)
    loss = F.cross_entropy(
        logits.view(-1, logits.size(-1)),
        y.view(-1),
        ignore_index=-1
    )
    # backprop and update the parameters
    loss.backward()
    xm.optimizer_step(optimizer) # XLA MP: performs grad allreduce and optimizer step
    pbar.set_description(f"Iteration: {idx}, train loss: {loss.item():.5f}")

# XLA: use xm.save instead of torch.save to ensure states are moved back to cpu
xm.save(model.state_dict(), "model.pt")