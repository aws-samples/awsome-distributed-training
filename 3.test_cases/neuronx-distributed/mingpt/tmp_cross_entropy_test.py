import torch
from torch.utils.data import DataLoader
from tqdm import tqdm
from torch.nn import functional as F
import torch_xla.core.xla_model as xm
# XLA imports for parallel loader and multi-processing
device = 'xla'

# Given tensors
x = torch.Tensor([
    [
        [0.0, 1.0, 0.0],
        [1.0, 0.0, 0.0]
    ],
    [
        [0.0, 0.0, 1.0],
        [0.0, 0.0, 1.0]
    ]
])
# Set requires_grad=True to enable gradient computation
x.requires_grad_(True)
y = torch.Tensor([[-1, 0], [-1, 0]]).long()
x, y = x.to(device), y.to(device)
loss = F.cross_entropy(x.view(-1, x.size(-1)), y.view(-1), ignore_index=-1)
print(loss)
loss.backward()
# # Mask out the elements where y is -1
# mask = (y != -1)
# 
# # Apply the mask to x and y
# x_masked = x[mask]
# y_masked = y[mask]
# 
# # Reshape x_masked to the appropriate dimensions for cross_entropy
# # x_masked should be of shape (N, C) where N is the number of samples and C is the number of classes
# x_masked = x_masked.view(-1, x.size(-1))
# # Ensure y_masked is 1D
# y_masked = y_masked.view(-1)
# 
# # Compute the cross-entropy loss
# loss = F.cross_entropy(x_masked, y_masked)
