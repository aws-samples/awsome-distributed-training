# Finetuning Llama from Huggingface Weights

This test case showcase how to finetune Llama2 model from HuuggingFace Weights using Megatron DeepSpeed.

## 1. Preparation
Set the following environment variables to run the test cases:

```bash
export CONTAINER_PATH=/fsxl/containers
export ENROOT_IMAGE=$CONTAINER_PATH/deepspeed.sqsh
export FSX_PATH=/fsxl
export MODEL_PATH=$FSX_PATH/deepspeed
export DATA_PATH=$FSX_PATH/alpaca
```
In this step, we prepares Llama2 dataset and pretrained weights.

This tutorial uses [Stanford Alphaca](https://github.com/tatsu-lab/stanford_alpaca) dataset. Download the dataset with the command below:

```bash
mkdir -p ${DATA_PATH}
wget https://raw.githubusercontent.com/tatsu-lab/stanford_alpaca/main/alpaca_data.json -O ${DATA_PATH}/alpaca_data.json
```

Llama2 model is governed by the Meta license and must be downloaded and converted to the standard [Hugging Face](https://huggingface.co/) format prior to running this sample.

### Option 1: Download from Hugging Face (Recommended)
1. Visit [meta-llama/Llama-2-7b](https://huggingface.co/meta-llama/Llama-2-7b) on Hugging Face
2. Accept the license terms and submit an access request (processed hourly)
3. Install Hugging Face CLI: `pip install -U "huggingface_hub[cli]"`
4. Login to Hugging Face: `huggingface-cli login`
5. Download the model to your desired location:
   ```bash
   hf download meta-llama/Llama-2-7b --local-dir ${MODEL_PATH}/Llama2-meta/7B
   hf download meta-llama/Llama-2-7b tokenizer.model --local-dir ${MODEL_PATH}/Llama2-meta
   ```

### Option 2: Download from Meta
1. Submit an access request from [Meta's Llama downloads page](https://www.llama.com/llama-downloads/)
2. You will receive an email with a signed download URL (valid for 24 hours)
3. Use the [download.sh](https://github.com/meta-llama/llama/blob/main/download.sh) script from the official repository
4. Run `./download.sh` and paste the URL from your email when prompted  

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

Convert the model weights into HF format:

```bash
sbatch 1.convert-weights-to-hf.sbatch
```

`convert_llama_weights_to_hf.py` transforms the original weights into the Huggingface format as in:

```
${MODEL_PATH}/Llama2-7b-hf
├── config.json
├── generation_config.json
├── pytorch_model-00001-of-00003.bin
├── pytorch_model-00002-of-00003.bin
├── pytorch_model-00003-of-00003.bin
├── pytorch_model.bin.index.json
├── special_tokens_map.json
├── tokenizer.json
├── tokenizer.model
└── tokenizer_config.json
```

Finally, transforms the checkpoint into Megatron DeepSpeed format:

```bash
bash 2.convert-weights-to-mega-ds.sh
```


## 1. Finetuning

Finetuning job can be submitted as follows:

```bash
bash 3.finetune-llama.sh
```