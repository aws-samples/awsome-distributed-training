## 3. Download llama3 model

Now fetch model weights and tokenizer with `2.download_hf_model.sbatch`:

```bash
sbatch download_hf_model.sbatch --HF_MODEL=meta-llama/Meta-Llama-3-70B
```

The model will be downloaded under ${}

You are all set ! P


## 4. Pretrain Llama3 model

In this step, you will author Llama3 model using c4 dataset with `torchtitan`.

```bash
sbatch 3.pretrain.sbatch
```

## 4. Finetune Llama3 model

In this step, you will fine tune llama model, using Alpaca dataset. 

```bash
sbatch 4.finetune.sbatch
```

Once the job has been completed, you will see following outputs in the log:

```bash
==> logs/convert-checkpoint_560.out <==
0: INFO:torchtune.utils.logging:Model checkpoint of size 4.97 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/hf_model_0024_0.pt
0: INFO:torchtune.utils.logging:Model checkpoint of size 4.66 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/hf_model_0025_0.pt
0: INFO:torchtune.utils.logging:Model checkpoint of size 4.66 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/hf_model_0026_0.pt
0: INFO:torchtune.utils.logging:Model checkpoint of size 4.66 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/hf_model_0027_0.pt
0: INFO:torchtune.utils.logging:Model checkpoint of size 5.00 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/hf_model_0028_0.pt
0: INFO:torchtune.utils.logging:Model checkpoint of size 4.97 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/hf_model_0029_0.pt
0: INFO:torchtune.utils.logging:Model checkpoint of size 2.10 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/hf_model_0030_0.pt
0: INFO:torchtune.utils.logging:Adapter checkpoint of size 0.09 GB saved to /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/adapter_0.pt
0: ^M1|3251|Loss: 1.5955958366394043: 100%|██████████| 3251/3251 [2:07:13<00:00,  2.35s/it]
```

checkpoints are saved as

```bash
$ ls /fsx/models/torchtitan-torchtune/meta-llama/Meta-Llama-3-70B-tuned/
adapter_0.pt        hf_model_0002_0.pt  hf_model_0005_0.pt  hf_model_0008_0.pt  hf_model_0011_0.pt  hf_model_0014_0.pt  hf_model_0017_0.pt  hf_model_0020_0.pt  hf_model_0023_0.pt  hf_model_0026_0.pt  hf_model_0029_0.pt
config.json         hf_model_0003_0.pt  hf_model_0006_0.pt  hf_model_0009_0.pt  hf_model_0012_0.pt  hf_model_0015_0.pt  hf_model_0018_0.pt  hf_model_0021_0.pt  hf_model_0024_0.pt  hf_model_0027_0.pt  hf_model_0030_0.pt
hf_model_0001_0.pt  hf_model_0004_0.pt  hf_model_0007_0.pt  hf_model_0010_0.pt  hf_model_0013_0.pt  hf_model_0016_0.pt  hf_model_0019_0.pt  hf_model_0022_0.pt  hf_model_0025_0.pt  hf_model_0028_0.pt
```

## 5. Evaluate Llama3 model with lm-evaluation harness

In this last section, you will evaluate Llama models. It will make use of [lm-evaluation-harness](https://github.com/EleutherAI/lm-evaluation-harness). 

You can submit sample evaluation job by:

```bash
sbatch 5.evaluate.sbatch
```

You will see:

```
Running loglikelihood requests:   6%|▋         | 23/400 [00:01<00:18, 20.53it/s]
Running loglikelihood requests:  16%|█▌        | 62/400 [00:02<00:15, 22.65it/s]
Running loglikelihood requests:  24%|██▍       | 98/400 [00:04<00:13, 22.50it/s]
Running loglikelihood requests:  33%|███▎      | 131/400 [00:06<00:12, 22.28it/s]
Running loglikelihood requests:  42%|████▏     | 164/400 [00:07<00:10, 22.40it/s]
Running loglikelihood requests:  50%|█████     | 200/400 [00:09<00:08, 22.60it/s]
Running loglikelihood requests:  58%|█████▊    | 233/400 [00:10<00:07, 22.46it/s]
Running loglikelihood requests:  66%|██████▌   | 263/400 [00:11<00:06, 22.51it/s]
Running loglikelihood requests:  74%|███████▍  | 296/400 [00:13<00:04, 22.45it/s]
Running loglikelihood requests:  82%|█�██████▏ | 326/400 [00:14<00:03, 22.63it/s]/s]
Running loglikelihood requests:  90%|████████▉ | 356/400 [00:16<00:01, 22.82it/s]
Running loglikelihood requests:  97%|█████████▋| 389/400 [00:17<00:00, 23.11it/s]
Running loglikelihood requests: 100%|██████████| 400/400 [00:17<00:00, 22.27it/s]
0: fatal: not a git repository (or any of the parent directories): .git
0: 2024-05-07:01:12:39,479 INFO     [eval.py:69] vllm (pretrained=meta-llama/Meta-Llama-3-70B,tensor_parallel_size=8,dtype=auto,gpu_memory_utilization=0.8,data_parallel_size=1), gen_kwargs: (None), limit: 100.0, num_fewshot: None, batch_size: 1
0: 2024-05-07:01:12:39,536 INFO     [eval.py:70] |  Tasks  |Version|Filter|n-shot| Metric |Value|   |Stderr|
0: |---------|------:|------|-----:|--------|----:|---|-----:|
0: |hellaswag|      1|none  |     0|acc     | 0.56|±  |0.0499|
0: |         |       |none  |     0|acc_norm| 0.75|±  |0.0435|
0: 
```



## 5. Chat with Finetuned model

Now that you can test the finetuned-model deployment using vLLM. 

```bash
sbatch 7.generate.sbatch --config configs/generate_llama3.yaml --prompt "Hello, my name is"
```

```
[generate.py:122] Hello, my name is Sarah and I am a busy working mum of two young children, living in the North East of England.
...
[generate.py:135] Time for inference: 10.88 sec total, 18.94 tokens/sec
[generate.py:138] Bandwidth achieved: 346.09 GB/s
[generate.py:139] Memory used: 18.31 GB
```