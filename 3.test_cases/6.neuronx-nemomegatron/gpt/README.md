
```bash
export DATA_DIR=/fsx/data/gpt2
mkdir -p ${DATA_DIR} && cd ${DATA_DIR}
wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-vocab.json
wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-merges.txt
aws s3 cp s3://neuron-s3/training_datasets/gpt/wikipedia/my-gpt2_text_document.bin .  --no-sign-request
aws s3 cp s3://neuron-s3/training_datasets/gpt/wikipedia/my-gpt2_text_document.idx .  --no-sign-request
aws s3 cp s3://neuron-s3/training_datasets/gpt/wikipedia/license.txt .  --no-sign-request
```