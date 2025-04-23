from datasets import load_dataset

# Download and cache the English C4 dataset
dataset = load_dataset("allenai/c4", 
                      name="en",
                      cache_dir="/fsx/datasets/c4")