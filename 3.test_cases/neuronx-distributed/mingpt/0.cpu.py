import torch
from torch.utils.data import DataLoader
from tqdm import tqdm

from torch.nn import functional as F
from mingpt.model import GPT
from mingpt.datasets import SortDataset 
from mingpt.configs import TrainConfig
from mingpt.utils import evaluate

# create train and test dataset
length = 6
num_digits = 3
train_dataset = SortDataset('train', length, num_digits)
test_dataset = SortDataset('test', length, num_digits)
train_config = TrainConfig.get_default_config()
train_loader = DataLoader(
    train_dataset,
    batch_size=train_config.batch_size,
)
test_loader = DataLoader(
    test_dataset,
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
    optimizer.step()
    pbar.set_description(f"Iteration: {idx}, train loss: {loss.item():.5f}")

model.eval()
print("Evaluate performance with train_loader")
evaluate(model, train_loader, length, max_batches=50)
print("Evaluate performance with test_loader")
evaluate(model, test_loader, length, max_batches=50)