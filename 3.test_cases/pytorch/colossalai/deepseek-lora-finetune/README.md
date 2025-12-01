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
export MODEL_NAME="deepseek-ai/DeepSeek-R1"
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
Example output on 15 p5en nodes(DP5, PP3, EP8):
```
Step:   3%|▎         | 6/224 [22:39<5:48:26, 95.90s/it, loss=00.794, grad_norm=0.161]
Step:   5%|▌         | 12/224 [25:24<2:14:47, 37.97s/it, loss=0.506, grad_norm=0.108]
Step:   8%|▊         | 17/224 [28:09<1:38:50, 28.65s/it, loss=0.442, grad_norm=0.124]
Step:  10%|█         | 23/224 [30:54<1:32:21, 27.57s/it, loss=0.429, grad_norm=0.0904]
Step:  13%|█▎        | 29/224 [33:16<1:34:26, 29.06s/it, loss=0.411, grad_norm=0.0404]
Step:  16%|█▌        | 34/224 [36:55<1:43:15, 32.61s/it, loss=0.383, grad_norm=0.0298]
Step:  18%|█▊        | 40/224 [40:09<1:33:32, 30.50s/it, loss=0.368, grad_norm=0.0255]
Step:  21%|██        | 46/224 [42:27<1:22:43, 27.89s/it, loss=0.367, grad_norm=0.0252]
Step:  23%|██▎       | 51/224 [45:13<1:19:52, 27.70s/it, loss=0.354, grad_norm=0.0262]
Step:  25%|██▌       | 57/224 [47:31<1:16:52, 27.62s/it, loss=0.346, grad_norm=0.0232]
Step:  28%|██▊       | 62/224 [50:16<1:14:09, 27.47s/it, loss=0.355, grad_norm=0.0211]
Step:  30%|███       | 68/224 [52:34<1:11:46, 27.61s/it, loss=0.336, grad_norm=0.0214]
Step:  33%|███▎      | 73/224 [55:36<1:14:31, 29.61s/it, loss=0.34, ggrad_norm=0.021]
Step:  35%|███▌      | 79/224 [57:57<1:07:50, 28.01s/it, loss=0.339, grad_norm=0.0212]
Step:  38%|███▊      | 84/224 [1:00:27<1:13:01, 31.30s/it, loss=0.325, grad_norm=0.0224]
Step:  40%|███▉      | 89/224 [1:03:35<1:07:18, 29.92s/it, loss=0.324, grad_norm=0.0206]
Step:  42%|████▏     | 95/224 [1:05:52<1:00:10, 27.78s/it, loss=0.338, grad_norm=0.0224]
Step:  45%|████▍     | 100/224 [1:08:08<56:34, 27.37s/it, loss=0.325, grad_norm=0.0213]
Step:  47%|████▋     | 105/224 [1:10:53<54:21, 27.41s/it, loss=0.318, grad_norm=0.0206]
Step:  49%|████▉     | 110/224 [1:13:11<51:55, 27.33s/it, loss=0.342, grad_norm=0.0208]
Step:  52%|█████▏    | 116/224 [1:15:40<51:53, 28.56s/it, loss=0.334, grad_norm=0.0214]
Step:  54%|█████▍    | 121/224 [1:18:04<48:21, 28.62s/it, loss=0.336, grad_norm=0.02]
Step:  56%|█████▋    | 126/224 [1:20:21<44:45, 27.40s/it, loss=0.33, grad_norm=0.0211]
Step:  58%|█████▊    | 131/224 [1:22:38<42:28, 27.41s/it, loss=0.326, grad_norm=0.022]
Step:  61%|██████    | 136/224 [1:25:29<46:47, 31.90s/it, loss=0.344, grad_norm=0.0233]
Step:  63%|██████▎   | 141/224 [1:28:45<38:47, 28.05s/it, loss=0.328, grad_norm=0.0218]
Step:  65%|██████▌   | 146/224 [1:30:29<35:42, 27.47s/it, loss=0.329, grad_norm=0.0218]
Step:  67%|██████▋   | 151/224 [1:32:47<33:11, 27.28s/it, loss=0.33, grad_norm=0.0208]
Step:  70%|██████▉   | 156/224 [1:35:16<32:35, 28.75s/it, loss=0.322, grad_norm=0.0216]
Step:  72%|███████▏  | 161/224 [1:37:37<30:45, 29.29s/it, loss=0.328, grad_norm=0.0238]
Step:  74%|███████▍  | 166/224 [1:39:26<26:40, 27.60s/it, loss=0.313, grad_norm=0.0236]
Step:  76%|███████▋  | 171/224 [1:41:43<24:12, 27.40s/it, loss=0.337, grad_norm=0.0435]
Step:  79%|███████▊  | 176/224 [1:44:00<21:54, 27.39s/it, loss=0.328, grad_norm=0.0222]
Step:  81%|████████  | 181/224 [1:46:24<21:01, 29.35s/it, loss=0.332, grad_norm=0.0226]
Step:  83%|████████▎ | 186/224 [1:49:02<18:43, 29.57s/it, loss=0.329, grad_norm=0.0215]
Step:  85%|████████▌ | 191/224 [1:51:18<15:45, 27.81s/it, loss=0.325, grad_norm=0.0217]
Step:  88%|████████▋ | 195/224 [1:53:42<14:02, 29.06s/it, loss=0.331, grad_norm=0.0221]
Step:  89%|████████▉ | 200/224 [1:55:59<11:04, 27.69s/it, loss=0.32, grad_norm=0.0207]
Step:  92%|█████████▏| 205/224 [1:58:00<09:17, 29.32s/it, loss=0.311, grad_norm=0.0224]
Step:  94%|█████████▍| 210/224 [2:00:16<06:27, 27.64s/it, loss=0.327, grad_norm=0.023]
Step:  96%|█████████▌| 214/224 [2:02:34<04:35, 27.57s/it, loss=0.315, grad_norm=0.0273]
Step:  98%|█████████▊| 219/224 [2:04:50<02:16, 27.38s/it, loss=0.348, grad_norm=0.0217]
Step: 100%|██████████| 224/224 [2:06:39<00:00, 27.30s/it, loss=0.325, grad_norm=0.0236]

Start saving final model checkpoint to /workdir/deepseek-ai/DeepSeek-R1-bf16-lora
Saved final model checkpoint at epoch 0 at folder /workdir/deepseek-ai/DeepSeek-R1-bf16-lora in 63.06 seconds

```

## Launch LoRA evaluation

```bash
srun \
    --mpi=pmix --cpu-bind=none \
    --container-image ../colossalai.sqsh \
    --container-mounts ./:/workdir,$HF_HOME:$HF_HOME \
    python /workdir/lora_eval.py -m deepseek-ai/DeepSeek-R1 -d AI-MO/NuminaMath-TIR
```
