import torch
from torch.utils.data import DataLoader
from tqdm import tqdm

from mingpt.model import GPT
from mingpt.datasets import SortDataset 
from mingpt.trainer import Trainer
from mingpt.configs import TrainConfig

# create train and test dataset
train_dataset = SortDataset('train')
test_dataset = SortDataset('test')
train_config = TrainConfig.get_default_config()
train_loader = DataLoader(
    train_dataset,
    batch_size=train_config.batch_size,
    )

# create a GPT instance
model_config = GPT.get_default_config()
model_config.model_type = 'gpt-nano'
model_config.vocab_size = train_dataset.get_vocab_size()
model_config.block_size = train_dataset.get_block_size()
model = GPT(model_config)
optimizer = model.configure_optimizers(train_config)

model.train()
pbar = tqdm(enumerate(train_loader))
for idx, (x, y) in pbar:
    # forward the model
    logits, loss = model(x, y)
    # backprop and update the parameters
    model.zero_grad(set_to_none=True)
    loss.backward()
    torch.nn.utils.clip_grad_norm_(model.parameters(), train_config.grad_norm_clip)
    optimizer.step()
    pbar.set_description(f"Iteration: {idx}, train loss: {loss.item():.5f}")