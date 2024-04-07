# Finetuning Llama from Huggingface Weights

This test case showcase how to finetune Llama2 model from HuuggingFace Weights using Megatron DeepSpeed.

## 1. Preparation

In this step, we prepares Llama2 pretrained weight and book sample dataset.


This test case requires Llama2 model, which governed by the Meta license and must be downloaded and converted to the standard [Hugging Face](https://huggingface.co/) format prior to running this sample.
You can submit access request from [here](https://ai.meta.com/resources/models-and-libraries/llama-downloads/), we need "Llama 2 & Llama Chat" to be checked. Use the [download.sh](https://github.com/facebookresearch/llama/blob/main/download.sh) in the official repository. You will be asked to input an URL from the email you recieve from meta.  

We will assume that you had placed the model and tokenizer as follows on cluster:

```
${MODEL_PATH}/Llama2-meta/
├── 7B/
│   ├── checklist.chk
│   ├── consolidated.00.pth
│   └── params.json
├── tokenizer.model
└── tokenizer_checklist.chk
```

