
```bash
python create_config.py --out_dir tmp --dp 4 --tp 2 --pp 2 --pp_engine 1f1b --exp_name llama-7B-CPU-dp4-tp2-pp2 --model_name meta-llama/Llama-2-7b-hf  --grad_acc_steps 32 --mbs 4 --seq_len 1024 --hf_token ${HF_TOKEN}
```
