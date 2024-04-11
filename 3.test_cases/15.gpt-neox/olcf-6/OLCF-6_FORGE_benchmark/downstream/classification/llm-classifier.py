import pandas as pd
import numpy as np
import torch
from transformers import BertTokenizer, BertModel, GPT2Model, GPT2Tokenizer
from torch import nn
from torch.optim import Adam
from tqdm import tqdm
import os, argparse

labels = {'material':0,
          'physics':1,
          'chemistry':2,
          'cs':3,
          'medical':4,
          'socialscience':5
          }


class Dataset(torch.utils.data.Dataset):

    def __init__(self, df, tokenizer, max_len=512):

        self.labels = [labels[label] for label in df['category']]
        self.texts = [tokenizer(text, 
                               padding='max_length', max_length = max_len, truncation=True,
                                return_tensors="pt") for text in df['text']]

    def classes(self):
        return self.labels

    def __len__(self):
        return len(self.labels)

    def get_batch_labels(self, idx):
        return np.array(self.labels[idx])

    def get_batch_texts(self, idx):
        return self.texts[idx]

    def __getitem__(self, idx):

        batch_texts = self.get_batch_texts(idx)
        batch_y = self.get_batch_labels(idx)

        return batch_texts, batch_y



class BertClassifier(nn.Module):

    def __init__(self, HFmodel, emb_size=768, nclasses=6, dropout=0.5):

        super(BertClassifier, self).__init__()

        self.bert = BertModel.from_pretrained(HFmodel)
        self.dropout = nn.Dropout(dropout)
        self.linear = nn.Linear(emb_size, nclasses)
        self.relu = nn.ReLU()

    def forward(self, input_id, mask):

        _, pooled_output = self.bert(input_ids= input_id, attention_mask=mask,return_dict=False)
        dropout_output = self.dropout(pooled_output)
        linear_output = self.linear(dropout_output)
        final_layer = self.relu(linear_output)

        return final_layer

class GptClassifier(nn.Module):
    def __init__(self, HFmodel, emb_size=768, seq_len=128, nclasses=6, dropout=0.5):
        super(GptClassifier, self).__init__()
        self.gpt = GPT2Model.from_pretrained(HFmodel)
        self.dropout = nn.Dropout(dropout)
        self.linear = nn.Linear(emb_size*seq_len, nclasses)

    def forward(self, input_id, mask):
        gpt_out, _ = self.gpt(input_ids=input_id, attention_mask=mask, return_dict=False)
        batch_size = gpt_out.shape[0]
        dropout_output = self.dropout(gpt_out.view(batch_size,-1))
        linear_output = self.linear(dropout_output)
        return linear_output
        

def train(model, train_data, val_data, tokenizer, learning_rate, epochs):

    train, val = Dataset(train_data, tokenizer), Dataset(val_data, tokenizer)

    train_dataloader = torch.utils.data.DataLoader(train, batch_size=2, shuffle=True)
    val_dataloader = torch.utils.data.DataLoader(val, batch_size=2)

    use_cuda = torch.cuda.is_available()
    device = torch.device("cuda" if use_cuda else "cpu")

    criterion = nn.CrossEntropyLoss()
    optimizer = Adam(model.parameters(), lr= learning_rate)

    if use_cuda:

            model = model.cuda()
            criterion = criterion.cuda()

    for epoch_num in range(epochs):

            total_acc_train = 0
            total_loss_train = 0

            for train_input, train_label in tqdm(train_dataloader):

                train_label = train_label.to(device)
                mask = train_input['attention_mask'].to(device)
                input_id = train_input['input_ids'].squeeze(1).to(device)

                output = model(input_id, mask)
                
                batch_loss = criterion(output, train_label.long())
                total_loss_train += batch_loss.item()
                
                acc = (output.argmax(dim=1) == train_label).sum().item()
                total_acc_train += acc

                model.zero_grad()
                batch_loss.backward()
                optimizer.step()
            
            total_acc_val = 0
            total_loss_val = 0

            with torch.no_grad():

                for val_input, val_label in val_dataloader:

                    val_label = val_label.to(device)
                    mask = val_input['attention_mask'].to(device)
                    input_id = val_input['input_ids'].squeeze(1).to(device)

                    output = model(input_id, mask)

                    batch_loss = criterion(output, val_label.long())
                    total_loss_val += batch_loss.item()
                    
                    acc = (output.argmax(dim=1) == val_label).sum().item()
                    total_acc_val += acc
            
            print(
                f'Epochs: {epoch_num + 1} | Train Loss: {total_loss_train / len(train_data): .3f} | Train Accuracy: {total_acc_train / len(train_data): .3f} | Val Loss: {total_loss_val / len(val_data): .3f} | Val Accuracy: {total_acc_val / len(val_data): .3f}')
                  
def evaluate(model, test_data, tokenizer):

    test = Dataset(test_data, tokenizer)

    test_dataloader = torch.utils.data.DataLoader(test, batch_size=2)

    use_cuda = torch.cuda.is_available()
    device = torch.device("cuda" if use_cuda else "cpu")

    if use_cuda:

        model = model.cuda()

    total_acc_test = 0
    with torch.no_grad():

        for test_input, test_label in test_dataloader:

              test_label = test_label.to(device)
              mask = test_input['attention_mask'].to(device)
              input_id = test_input['input_ids'].squeeze(1).to(device)

              output = model(input_id, mask)

              acc = (output.argmax(dim=1) == test_label).sum().item()
              total_acc_test += acc
    
    print(f'Test Accuracy: {total_acc_test / len(test_data): .3f}')

if __name__ == "__main__":
    np.random.seed(112)
    parser = argparse.ArgumentParser(description='TFT-Topaz command line arguments',\
            formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('--input', default=os.path.expanduser('./domains.csv'), help='input csv file')
    parser.add_argument('--model', default='bert-base-cased', help='hugginface model')
    parser.add_argument('--emb-size', default=768, type=int, help='hugginface model')
    parser.add_argument('--seq-len', default=512, type=int, help='hugginface model')
    args = parser.parse_args()

    datapath = args.input
    HFmodel = args.model
    emb_size = args.emb_size
    seq_len = args.seq_len
    df = pd.read_csv(datapath)
    if 'bert' in HFmodel:
        tokenizer = BertTokenizer.from_pretrained(HFmodel)
    elif 'gpt' in HFmodel:
        tokenizer = GPT2Tokenizer.from_pretrained(HFmodel)
        tokenizer.padding_side = "left"
        tokenizer.pad_token = tokenizer.eos_token

    df_train, df_val, df_test = np.split(df.sample(frac=1, random_state=42), 
                                         [int(.8*len(df)), int(.9*len(df))])

    print(len(df_train),len(df_val), len(df_test))


    EPOCHS = 5
    LR = 1e-6
    if 'bert' in HFmodel:
        model = BertClassifier(HFmodel, emb_size, nclasses=len(labels))
    elif 'gpt' in HFmodel:
        model = GptClassifier(HFmodel, emb_size, seq_len, nclasses=len(labels))
   
                  
    train(model, df_train, df_val, tokenizer, LR, EPOCHS)
    
    evaluate(model, df_test, tokenizer)
