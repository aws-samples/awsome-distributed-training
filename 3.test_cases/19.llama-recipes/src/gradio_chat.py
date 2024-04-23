import os 
import gradio as gr
from transformers import AutoModelForCausalLM, AutoTokenizer
import sys
sys.path.append("/fsx/awsome-distributed-training/3.test_cases/19.llama-recipes/llama3/llama")
from generation import Llama

from typing import Tuple
import os
import sys
import torch
import fire
import time
import json

from pathlib import Path

from fairscale.nn.model_parallel.initialize import initialize_model_parallel

from model import ModelArgs, Transformer
from generation import Llama
from tokenizer import Tokenizer


# def setup_model_parallel() -> Tuple[int, int]:
#     local_rank = int(os.environ.get("LOCAL_RANK", -1))
#     world_size = int(os.environ.get("WORLD_SIZE", -1))
# 
#     torch.distributed.init_process_group("nccl")
#     initialize_model_parallel(world_size)
#     torch.cuda.set_device(local_rank)
# 
#     # seed must be the same in all processes
#     torch.manual_seed(1)
#     return local_rank, world_size
# 
# 
# def load(ckpt_dir: str, tokenizer_path: str, local_rank: int, world_size: int) -> Llama:
#     start_time = time.time()
#     checkpoints = sorted(Path(ckpt_dir).glob("*.pth"))
#     assert (
#         world_size == len(checkpoints)
#     ), f"Loading a checkpoint for MP={len(checkpoints)} but world size is {world_size}"
#     ckpt_path = checkpoints[local_rank]
#     print("Loading")
#     checkpoint = torch.load(ckpt_path, map_location="cpu")
#     with open(Path(ckpt_dir) / "params.json", "r") as f:
#         params = json.loads(f.read())
# 
#     model_args: ModelArgs = ModelArgs(max_seq_len=512, max_batch_size=32, **params)
#     tokenizer = Tokenizer(model_path=tokenizer_path)
#     model_args.vocab_size = tokenizer.n_words
#     torch.set_default_tensor_type(torch.cuda.HalfTensor)
#     model = Transformer(model_args)
#     torch.set_default_tensor_type(torch.FloatTensor)
#     model.load_state_dict(checkpoint, strict=False)
# 
#     generator = Llama(model, tokenizer)
#     print(f"Loaded in {time.time() - start_time:.2f} seconds")
#     return generator
# 
# local_rank = int(os.environ.get("LOCAL_RANK", -1))
# world_size = int(os.environ.get("WORLD_SIZE", -1))
# 
# torch.distributed.init_process_group("nccl")
# initialize_model_parallel(world_size)
# torch.cuda.set_device(local_rank)
# torch.manual_seed(1)
# 
# generator = load(
#     ckpt_dir="/fsx/models/meta-llama/Meta-Llama-3-70B",
#     tokenizer_path="/fsx/models/meta-llama/Meta-Llama-3-70B/tokenizer.model",
#     local_rank=local_rank,
#     world_size=world_size
# )
# 
# def generate_text(text):
#     return generator.text_completion([text], max_gen_len=512)
# 
# examples = [
#     # For these prompts, the expected answer is the natural continuation of the prompt
#     "I believe the meaning of life is",
#     "Simply put, the theory of relativity states that ",
#     "Building a website can be done in 10 simple steps:\n",
#     # Few shot prompts: https://huggingface.co/blog/few-shot-learning-gpt-neo-and-inference-api
#     """Tweet: "I hate it when my phone battery dies."
# Sentiment: Negative
# ###
# Tweet: "My day has been 👍"
# Sentiment: Positive
# ###
# Tweet: "This is the link to the article"
# Sentiment: Neutral
# ###
# Tweet: "This new music video was incredibile"
# Sentiment:""",
#     """Translate English to French:
# sea otter => loutre de mer
# peppermint => menthe poivrée
# plush girafe => girafe peluche
# cheese =>""",
#     ]
# 
# if local_rank == 0:
#     gr.Interface(
#         generate_text,
#         "textbox",
#         "text",
#         title="LLama 7B",
#         description="LLama-7B large language model.",
#         examples=examples
#     ).queue().launch(share=True)

# Load the model and tokenizer
# model_name = "meta-llama/Meta-Llama-3-70B"  # Replace with the actual model name
# tokenizer = AutoTokenizer.from_pretrained(model_name)
generator = Llama.build(
    ckpt_dir="/fsx/models/meta-llama/Meta-Llama-3-8B",
    tokenizer_path="/fsx/models/meta-llama/Meta-Llama-3-8B/tokenizer.model",
    max_seq_len=2048,
    max_batch_size=1,
)

def format_prompt(user_input, chat_history=None, system_prompt=None):
    """
    Formats the prompt for the Llama2 model according to the expected chat instruction format.
    
    Parameters:
    - user_input (str): The user's input message or question.
    - chat_history (list of tuples): A list containing tuples of (user_input, model_response).
    - system_prompt (str): Optional system-level prompt that can be used to guide the model's responses.
    
    Returns:
    - str: A formatted prompt string ready to be processed by the Llama2 model.
    """
    print("user_input: ", user_input)
    # prompt = ""
    
    # # Include system prompt if provided
    # if system_prompt:
    #     prompt += f"System: {system_prompt}\n"
    
    # # Add chat history to the prompt
    # if chat_history:
    #     for user_msg, model_resp in chat_history:
    #         prompt += f"User: {user_msg}\n"
    #         prompt += f"Model: {model_resp}\n"
    #
    # Add the current user input to the prompt
    #prompt += f"User: {user_input}\n"
    
    return [[{"role": "user", "content": user_input}]]

# Define a function to generate responses
def generate_response(user_input, chat_history=None):
    # Format the prompt as required by the model
    dialogs = format_prompt(user_input, chat_history)
    temperature = 0.6
    max_gen_len = None
    top_p = 0.9
    # Generate a response
    results = generator.chat_completion(
        dialogs,
        max_gen_len=max_gen_len,
        temperature=temperature,
        top_p=top_p,
    )
    
    # # Update chat history
    # chat_history.append((user_input, response))
    
    # return results["generation"]["content"]
    return results # ["generation"]["content"]

#print(generate_response("this is test"))
# Create the Gradio interface
rank = int(os.environ["RANK"])
if rank == 0:
    iface = gr.Interface(
        fn=generate_response,
        inputs=["text"],
        outputs="text"
    )

    # Launch the interface
    iface.launch(share=True)
