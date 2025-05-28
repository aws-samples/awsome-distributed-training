# DeepSeek V3/R1/Prover-V2 671B SFT with LoRA

This example uses Colossal-AI container from the parent directory

## Download model weights

```bash
pip install -U "huggingface_hub[cli]"
```

Choose the model you want to finetune:

 - deepseek-ai/DeepSeek-V3
 - deepseek-ai/DeepSeek-V3-0324
 - deepseek-ai/DeepSeek-R1
 - deepseek-ai/DeepSeek-Prover-V2-671B

and define model name environment variable, for example:
```bash
export MODEL_NAME="deepseek-ai/DeepSeek-Prover-V2-671B"
```

Download the model weights from Hugging Face and find the model path:
```bash
huggingface-cli download $MODEL_NAME
export MODEL_PATH=`python -c "from pathlib import Path; from huggingface_hub import hf_hub_download; print(Path(hf_hub_download('$MODEL_NAME', filename='config.json')).parent)"`
export HF_HOME=${HF_HOME:-$(python -c "from pathlib import Path; from huggingface_hub import hf_hub_download; print(Path(hf_hub_download('$MODEL_NAME', filename='config.json')).parent.parent.parent.parent.parent)")}
```

## Convert fp8 weights to bf16

Since the model weights are fp8 and SFT requires bf16 weights, we use `convert_to_bf16.py` from `DeepSeek-V3` repo to convert the weights to bf16:

Clone DeepSeek V3 repo:
```bash
git clone https://github.com/deepseek-ai/DeepSeek-V3.git
```
Launch a job on the GPU node:
```bash
srun \
    --container-image ../colossalai.sqsh \
    --container-mounts ./:/workdir,$HF_HOME:$HF_HOME \
    python /workdir/DeepSeek-V3/inference/fp8_cast_bf16.py \
        --input-fp8-hf-path $MODEL_PATH \
        --output-bf16-hf-path /workdir/$MODEL_NAME-bf16
```

Copy the model config and tokenizer files to the output directory:
```bash
cp -L $MODEL_PATH/*.json ./$MODEL_NAME-bf16/
cp -L $MODEL_PATH/*.py ./$MODEL_NAME-bf16/
```

## Launch LoRA finetuning

```bash
sbatch lora_finetune.sbatch $MODEL_NAME AI-MO/NuminaMath-TIR train
```
Check the logs:
```bash
tail -f -n +0 slurm-XXX.out
```

## Launch LoRA evaluation

```bash
srun \
    --mpi=pmix --cpu-bind=none \
    --container-image ../colossalai.sqsh \
    --container-mounts ./:/workdir,$HF_HOME:$HF_HOME \
    python /workdir/lora_eval.py -m deepseek-ai/DeepSeek-Prover-V2-7B -d AI-MO/NuminaMath-TIR
```
