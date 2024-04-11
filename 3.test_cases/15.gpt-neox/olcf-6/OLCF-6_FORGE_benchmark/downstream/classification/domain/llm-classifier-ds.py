import pandas as pd
import numpy as np
import torch
from transformers import BertTokenizer, BertModel, GPT2Model, GPT2Tokenizer
from torch import nn
from transformers import GPTNeoXForCausalLM, GPTNeoXTokenizerFast
from torch.optim import Adam
from tqdm import tqdm
import os, argparse
import torch
import numpy as np
#from transformers import BertTokenizerFast, BertModelForTokenClassification
from transformers import DataCollatorForLanguageModeling, DataCollatorWithPadding
from torch.utils.data import DataLoader, Dataset
import pandas as pd
import numpy as np
import torch
from transformers import BertForTokenClassification, BertTokenizer, BertTokenizerFast, BertModel, GPT2Model, GPT2Tokenizer, AutoModelForTokenClassification, AutoTokenizer, AutoConfig
from transformers import BertForTokenClassification
from torch import nn
from torch.optim import Adam, SGD
from tqdm import tqdm
import os, argparse
from torch.nn import BCEWithLogitsLoss, CrossEntropyLoss, MSELoss
from transformers import Trainer
from transformers import TrainingArguments
from transformers import HfArgumentParser, set_seed
from dataclasses import dataclass, field
from typing import Optional

labels = {'material':0,
          'physics':1,
          'chemistry':2,
          'cs':3,
          'medical':4,
          'socialscience':5
          }

@dataclass
class ModelArguments:
    """
    Arguments pertaining to which model/config/tokenizer we are going to fine-tune from.
    """
    model_name_or_path: str = field(
        default=None
    )
    savepath: str = field(
        default="./pretrained"
    )
    max_len: int = field(
        default=128
    )

class Dataset(torch.utils.data.Dataset):

    def __init__(self, df, tokenizer, max_len=512):

        self.labels = [labels[label] for label in df['category']]
        #self.texts = [tokenizer(text, 
        #                       padding='max_length', max_length = max_len, truncation=True,
        #                        return_tensors="pt") for text in df['text']]
        self.texts = df["text"]
        
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
        #item = batch_texts
        #item["labels"] = batch_y
        return batch_texts, batch_y



class BertClassifier(nn.Module):

    def __init__(self, HFmodel, emb_size=768, nclasses=6, dropout=0.5):

        super(BertClassifier, self).__init__()

        self.bert = BertModel.from_pretrained(HFmodel)
        self.dropout = nn.Dropout(dropout)
        self.linear = nn.Linear(emb_size, nclasses)
        self.relu = nn.ReLU()

    def forward(self, input_ids, attention_mask, labels):

        _, pooled_output = self.bert(input_ids= input_ids, attention_mask=attention_mask,return_dict=False)
        dropout_output = self.dropout(pooled_output)
        linear_output = self.linear(dropout_output)
        final_layer = self.relu(linear_output)

        return final_layer

class GptClassifier(nn.Module):
    def __init__(self, HFmodel, emb_size=768, seq_len=512, nclasses=6, dropout=0.5):
        super(GptClassifier, self).__init__()
        self.gpt = GPT2Model.from_pretrained(HFmodel)
        self.dropout = nn.Dropout(dropout)
        self.linear = nn.Linear(emb_size*seq_len, nclasses)

    def forward(self, input_ids, attention_mask, labels):
        gpt_out, _ = self.gpt(input_ids=input_ids, attention_mask=attention_mask, return_dict=False)
        batch_size = gpt_out.shape[0]
        dropout_output = self.dropout(gpt_out.view(batch_size,-1))
        linear_output = self.linear(dropout_output)

        logits = linear_output
        loss_fct = CrossEntropyLoss()
        #loss = loss_fct(logits.view(-1, self.num_labels), labels.view(-1))
        loss = loss_fct(logits, labels)
        print("loss=", loss)
        return {"loss" : loss, "logits" : logits}
        #return linear_output
    
class GptClassifier2(nn.Module):
    def __init__(self, HFmodel, emb_size=768, seq_len=512, nclasses=6, dropout=0.5):
        super(GptClassifier2, self).__init__()
        self.gpt = GPTNeoXForCausalLM.from_pretrained(HFmodel)
        #print("gpt size:", self.gpt)
        self.dropout = nn.Dropout(dropout)
        self.linear = nn.Linear(52096*seq_len, nclasses)
        

    def forward(self, input_ids, attention_mask, labels):
        gpt_out, _ = self.gpt(input_ids=input_ids, attention_mask=attention_mask, return_dict=False)
        #print("gpt_out shape", gpt_out.shape)
        #gpt_out = gpt_out[0]
        batch_size = gpt_out.shape[0]
        #print("batch size=", batch_size)
        dropout_output = self.dropout(gpt_out.view(batch_size,-1))
        #print("dropout shape:", dropout_output.shape)
        
        linear_output = self.linear(dropout_output)
        loss_fct = CrossEntropyLoss()
        #print("Input to the loss function:", linear_output.shape, labels.shape)
        loss = loss_fct(linear_output, labels)
        return {"loss" : loss, "logits" : linear_output}

def accuracy_score(y_true, y_pred):
    """Accuracy classification score.
    In multilabel classification, this function computes subset accuracy:
    the set of labels predicted for a sample must *exactly* match the
    corresponding set of labels in y_true.
    Args:
        y_true : 2d array. Ground truth (correct) target values.
        y_pred : 2d array. Estimated targets as returned by a tagger.
    Returns:
        score : float.
    Example:
        >>> from seqeval.metrics import accuracy_score
        >>> y_true = [['O', 'O', 'O', 'B-MISC', 'I-MISC', 'I-MISC', 'O'], ['B-PER', 'I-PER', 'O']]
        >>> y_pred = [['O', 'O', 'B-MISC', 'I-MISC', 'I-MISC', 'I-MISC', 'O'], ['B-PER', 'I-PER', 'O']]
        >>> accuracy_score(y_true, y_pred)
        0.80
    """
    #print("y_true:", y_true)
    #print("y_pred:", y_pred)
    if any(isinstance(s, list) for s in y_true):
        y_true = [item for sublist in y_true for item in sublist]
        y_pred = [item for sublist in y_pred for item in sublist]

    nb_correct = sum(y_t == y_p for y_t, y_p in zip(y_true, y_pred))
    nb_true = len(y_true)
    print("pred:", y_pred)
    print("truth:", y_true)
    score = nb_correct / nb_true
    print("score =", score)
    return score


def compute_metrics(p):
    predictions, labels = p
    predictions = np.argmax(predictions, axis=1)
   
    score = accuracy_score(y_true=labels, y_pred=predictions)
    
    return {
        #"precision": results["overall_precision"],
        #"recall": results["overall_recall"],
        #"f1": results["overall_f1"],
        "accuracy": score,#results["overall_accuracy"],
    }



if __name__ == "__main__":
    np.random.seed(112)
    '''
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
    '''
    parser = HfArgumentParser((ModelArguments, TrainingArguments))
    model_args, training_args = parser.parse_args_into_dataclasses()
    datapath = "./domains.csv" 
    df = pd.read_csv(datapath)
    HFmodel = model_args.model_name_or_path
    print("Model name:", HFmodel)
    emb_size = 768
    seq_len = 512


    #if 'bert' in HFmodel:
    #    tokenizer = BertTokenizer.from_pretrained(HFmodel)
    #elif 'gpt' in HFmodel:
    tokenizer = GPTNeoXTokenizerFast.from_pretrained(HFmodel)
    #tokenizer = GPT2Tokenizer.from_pretrained("gpt2")
    tokenizer.padding_side = "left"
    tokenizer.pad_token = tokenizer.eos_token

    df_train, df_val, df_test = np.split(df.sample(frac=1, random_state=42), 
                                         [int(.8*len(df)), int(.9*len(df))])

    print(len(df_train),len(df_val), len(df_test))
  
    def preprocess_function(examples):
        #return tokenizer(examples["text"], truncation=False,)
        return tokenizer(examples["text"], padding='max_length', max_length = 512, truncation=True)#, return_tensors="pt")


    EPOCHS = 1
    LR = 1e-6
    #if 'bert' in HFmodel:
    #    model = BertClassifier(HFmodel, emb_size, nclasses=len(labels))
    #elif 'gpt' in HFmodel:
    model = GptClassifier2(HFmodel, emb_size, seq_len, nclasses=len(labels))
    #model = GptClassifier("gpt2", emb_size, seq_len, nclasses=len(labels)) 
    #print("GPTNeoX model:", model)
    data_collator = DataCollatorWithPadding(
        tokenizer=tokenizer, padding="max_length", max_length=512#, truncation=True#, max_length=768#, mlm=True, mlm_probability=0.15#, pad_to_multiple_of=1024
    )

    train_dataset, val_dataset = Dataset(df_train, tokenizer), Dataset(df_val, tokenizer) 
    import datasets
    train_dataset = datasets.Dataset.from_dict({"text" : train_dataset.texts, "labels" : train_dataset.labels})
    train_dataset = train_dataset.map(preprocess_function, batched=True)

    val_dataset = datasets.Dataset.from_dict({"text" : val_dataset.texts, "labels" : val_dataset.labels})
    val_dataset = val_dataset.map(preprocess_function, batched=True)
    #print("train_dataset:", train_dataset) 
    #print(len(train_dataset[0]["input_ids"]))
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_dataset,#tokenized_datasets["train"],
        eval_dataset=val_dataset,#tokenized_datasets["test"],
        tokenizer=tokenizer,
        data_collator=data_collator,
        compute_metrics=compute_metrics,
    )
    trainer.train()
    trainer.save_model(model_args.savepath)
    #train(model, df_train, df_val, tokenizer, LR, EPOCHS)
    
    #evaluate(model, df_test, tokenizer)
