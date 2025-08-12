# Performance

This document describes the process of performance measurements of NeMo 2.x framework.

Useful links and the original documentation:
* [NVIDIA NeMo Performance Summary](https://docs.nvidia.com/nemo-framework/user-guide/latest/performance/performance-summary.html)
* [NVIDIA NeMo Performance Scripts](https://github.com/NVIDIA/NeMo/tree/main/scripts/performance/llm)
* [NVIDIA NeMo Compatibility Matrix](https://docs.nvidia.com/nemo-framework/user-guide/latest/softwarecomponentversions.html)

### Create Conda Environment

```bash
conda create -yn nemo python=3.12
conda activate nemo
```

### Install NeMo

Make sure that Nemo version is compatible with the docker image according to the [compatibility matrix](https://docs.nvidia.com/nemo-framework/user-guide/latest/softwarecomponentversions.html)

```bash
git clone git@github.com:NVIDIA/NeMo.git
cd NeMo
git checkout v2.5.0rc0  # 2.4.0 was broken https://github.com/NVIDIA/NeMo/issues/14392
pip install -e '.[all]' # -e makes recommended model configs loadable
```

Optionally specify where to store the performance results:

```bash
export NEMORUN_HOME=/fsxl/.../nemo_run
```

### Build Docker Image

The docker file is supposed to start with `FROM nvcr.io/nvidia/nemo:YY.MM` and continue with EFA installation. Make sure that the docker image is compatible with the Nemo version according to the [compatibility matrix](https://docs.nvidia.com/nemo-framework/user-guide/latest/softwarecomponentversions.html)

```bash
docker build --progress=plain -t aws-nemo:latest -f Dockerfile .
enroot import -o ~/aws-nemo.sqsh dockerd://aws-nemo:latest
```

### Run Performance Test

To enable EFA just export environment variables:

```bash
export FI_PROVIDER=efa
export NCCL_DEBUG=INFO
```

## Pre-training Performance

## NVIDIA H100(also applicable to H200)

`NeMo/scripts/performance/recommended_model_configs/model_configs_h100.csv`

| Model     | #-GPUs | GBS | MBS | Sequence Length | TP | PP | CP | VP | EP | GA |
|-----------|--------|-----|-----|-----------------|----|----|----|----|----|----|
| LLAMA3-8B | 8      | 128 | 1   | 8192            | 1  | 1  | 2  | 1  | 1  | 32 |

```bash
python -m scripts.performance.llm.pretrain_llama3_8b \
    --account $(whoami) --partition p5en -i ./aws-nemo.sqsh \
    --gpu h100 --num_gpus 8 -gb 128 -mb 1 -tp 1 -pp 1 -cp 2 -vp 1 -ep 1
```

| Model      | #-GPUs | GBS | MBS | Sequence Length | TP | PP | CP | VP | EP | GA |
|------------|--------|-----|-----|-----------------|----|----|----|----|----|----|
| LLAMA3-70B | 64     | 128 | 1   | 8192            | 4  | 8  | 1  | 5  | 1  | 64 |

```bash
python -m scripts.performance.llm.pretrain_llama3_70b \
    --account $(whoami) --partition p5en -i ./aws-nemo.sqsh \
    --gpu h100 --num_gpus 64 -gb 128 -mb 1 -tp 4 -pp 8 -cp 1 -vp 5 -ep 1
```

| Model         | #-GPUs | GBS | MBS | Sequence Length | TP | PP | CP | VP | EP | GA |
|---------------|--------|-----|-----|-----------------|----|----|----|----|----|----|
| LLAMA3.1-405B | 128    | 64  | 1   | 8192            | 8  | 8  | 2  | 8  | 1  | 64 |

```bash
python -m scripts.performance.llm.pretrain_llama31_405b \
    --account $(whoami) --partition p5en -i ./aws-nemo.sqsh \
    --gpu h100 --num_gpus 128 -gb 64 -mb 1 -tp 8 -pp 8 -cp 2 -vp 8 -ep 1
```

## Fine-Tuning Performance

1. Specify `NEMO_HOME` explicitly to prevent `fiddle._src.experimental.serialization.UnserializableValueError`
https://docs.nvidia.com/nemo-framework/user-guide/latest/nemorun/faqs.html#q-unserializablevalueerror-when-using-run-partial-or-run-config

```bash
export NEMO_HOME=...
```

~~2. Append `FLOPsMeasurementCallback` for task == "none" in `set_exp_logging_configs` in `helpers.py` to get FLOPs measurements.~~

3. To enable `mxfp8` recipe, add `recipe.trainer.strategy.ddp.fp8_param_gather = True` in `finetune_llama3_8b.py`/`finetune_llama3_70b.py`
```python
if args.fp8_recipe == "mxfp8":
    recipe.trainer.strategy.ddp.fp8_param_gather = True
```

### NVIDIA B200

#### LLAMA3-8B SFT

| Model     | Task | #-GPUs | GBS | MBS | Packed Sequence Length | TP | PP | VP | GA |
|-----------|------|--------|-----|-----|------------------------|----|----|----|----|
| LLAMA3-8B | SFT  | 8      | 8   | 1   | 16384                  | 1  | 1  | 1  | 1  |

fp8:
```bash
python -m scripts.performance.llm.finetune_llama3_8b \
    --account $(whoami) --partition p6 -i ./aws-nemo.sqsh \
    -hf $HF_TOKEN \
    --gpu b200 -c fp8 -f sft --num_gpus 8 -gb 8 -mb 1 -tp 1 -pp 1 -vp 1
```
mxfp8:
```bash
python -m scripts.performance.llm.finetune_llama3_8b \
    --account $(whoami) --partition p6 -i ./aws-nemo.sqsh \
    -hf $HF_TOKEN \
    --gpu b200 -c fp8 -f sft --num_gpus 8 -gb 8 -mb 1 -tp 1 -pp 1 -vp 1 -fr mxfp8
```

#### LLAMA3-70B SFT

| Model      | Task | #-GPUs | GBS | MBS | Packed Sequence Length | TP | PP | VP | GA |
|------------|------|--------|-----|-----|------------------------|----|----|----|----|
| LLAMA3-70B | SFT  | 32     | 32  | 1   | 4096                   | 2  | 4  | 5  | 8  |

fp8:
```bash
python -m scripts.performance.llm.finetune_llama3_70b \
    --account $(whoami) --partition p6 -i ./aws-nemo.sqsh \
    -hf $HF_TOKEN \
    --gpu b200 -c fp8 -f sft --num_gpus 32 -gb 32 -mb 1 -tp 2 -pp 4 -vp 5
```
mxfp8:
```bash
python -m scripts.performance.llm.finetune_llama3_70b \
    --account $(whoami) --partition p6 -i ./aws-nemo.sqsh \
    -hf $HF_TOKEN \
    --gpu b200 -c fp8 -f sft --num_gpus 32 -gb 32 -mb 1 -tp 2 -pp 4 -vp 5 -fr mxfp8
```

#### LLAMA3-70B LoRA

| Model      | Task  | #-GPUs | GBS | MBS | Packed Sequence Length | TP | PP | VP | GA |
|------------|-------|--------|-----|-----|------------------------|----|----|----|----|
| LLAMA3-70B | LoRA  | 8      | 32  | 1   | 4096                   | 1  | 4  | 20 | 16 |

fp8:
```bash
python -m scripts.performance.llm.finetune_llama3_70b \
    --account $(whoami) --partition p6 -i ./aws-nemo.sqsh \
    -hf $HF_TOKEN \
    --gpu b200 -c fp8 -f lora --num_gpus 8 -gb 32 -mb 1 -tp 1 -pp 4 -vp 20
```
mxfp8:
```bash
python -m scripts.performance.llm.finetune_llama3_70b \
    --account $(whoami) --partition p6 -i ./aws-nemo.sqsh \
    -hf $HF_TOKEN \
    --gpu b200 -c fp8 -f lora --num_gpus 8 -gb 32 -mb 1 -tp 1 -pp 4 -vp 20 -fr mxfp8
```
