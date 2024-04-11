import jsonlines as jl
import json
from mpi4py import MPI
import sys
import os, argparse
from langdetect import detect 
import pandas as pd
import numpy as np
import torch
from transformers import AutoTokenizer, AutoModel
from torch import nn
from torch.optim import Adam

labels = {'material':0,
          'physics':1,
          'chemistry':2,
          'cs':3,
          'medical':4,
          'socialscience':5
          }

class Dataset(torch.utils.data.Dataset):

    def __init__(self, df, tokenizer, max_len=512):

        self.labels = [label for label in df['coreId']]
        self.texts = [tokenizer(text,
                               padding='max_length', max_length = max_len, truncation=True,
                                return_tensors="pt") for text in df['abstract']]

    def classes(self):
        return self.labels

    def __len__(self):
        return len(self.labels)

    def get_batch_labels(self, idx):
        # Fetch a batch of labels
        return np.array(self.labels[idx])

    def get_batch_texts(self, idx):
        # Fetch a batch of inputs
        return self.texts[idx]

    def __getitem__(self, idx):

        batch_texts = self.get_batch_texts(idx)
        batch_y = self.get_batch_labels(idx)

        return batch_texts, batch_y


def embed_func(df, model):
        
    model = torch.load(model)
    tokenizer = AutoTokenizer.from_pretrained('allenai/scibert_scivocab_uncased')

    dset = Dataset(df, tokenizer)
    loader = torch.utils.data.DataLoader(dset, batch_size=1024, shuffle=False)

    use_cuda = torch.cuda.is_available()
    device = torch.device("cuda" if use_cuda else "cpu")
    if use_cuda:
        model = model.to(device)

    model.eval()
    domains_chunks = []
    with torch.no_grad():
        for inputs, labels in loader:
            # preprocess the input
            mask = inputs['attention_mask'].to(device)
            input_id = inputs['input_ids'].squeeze(1).to(device)
            result = model(input_id, mask)
            domains = result[0].argmax(dim=1).cpu().detach().numpy()
            domains_chunks.append(domains)
    domains = np.concatenate(domains_chunks)

    return_df = (
        df[["coreId"]]
        .assign(domain=list(domains))
    )
    return return_df


if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='Inference command line arguments',\
            formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('--model', default=None, help='fine-tuned classifier model')
    parser.add_argument('--data_dir', default=None, help='input jsonl file')
    args = parser.parse_args()

    model = args.model
    data_dir = args.data_dir 

    comm = MPI.COMM_WORLD
    rank = comm.Get_rank()

    data = "%s/papers_%s.json"%(data_dir, str(rank))
    if not os.path.isfile(data):
        exit()

    json_writer = {}
    for domain,idx in labels.items():
        json_writer[idx] = jl.open("%s/abstracts_%s.json"%(os.path.join(data_dir,domain),str(rank)), mode="w")
    inputdf = pd.read_json(data, lines=True) 
    outdf = embed_func(inputdf, model)
   
    labels = np.array(list(outdf['domain'].values), dtype=int)
     
    with jl.open(data) as reader:
        for line, obj in enumerate(reader):
            text = obj["abstract"]
            if isinstance(obj["fullText"], str):
                text = text + obj["fullText"]  
            json_writer[labels[line]].write({"id": obj["coreId"], "text":text})  
