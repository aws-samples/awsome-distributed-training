python -m vllm.entrypoints.api_server --model "meta-llama/Meta-Llama-3-70B" --tensor-parallel-size 8 &
python src/gradio_chat.py