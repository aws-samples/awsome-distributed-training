import os
import torch
import argparse
from datasets import load_dataset
from peft import LoraConfig
from transformers import AutoModelForCausalLM, AutoTokenizer, set_seed
from optimum.neuron import NeuronSFTConfig, NeuronSFTTrainer
from optimum.neuron.distributed import lazy_load_for_parallelism
import torch_xla.core.xla_model as xm

HF_token = os.environ["HUGGINGFACE_TOKEN"]

def format_dolly(examples):
    """
    Format a set of examples into a specific prompt structure for the Dolly model.
    Args:
        examples (dict): A dictionary containing the following keys:
            instruction (list): A list of instruction strings.
            context (list): A list of context strings (optional).
            response (list): A list of response strings.
    Returns:
        list: A list of formatted prompt strings, each containing the instruction, context (if available), and response.
    """    

    output_text = []
    for i in range(len(examples["instruction"])):
        instruction = f"### Instruction\\n{examples['instruction'][i]}"
        context = f"### Context\\n{examples['context'][i]}" if examples["context"][i] else None
        response = f"### Answer\\n{examples['response'][i]}"
        prompt = "\\n\\n".join([i for i in [instruction, context, response] if i is not None])
        output_text.append(prompt)
    return output_text

def training_function(args):
    """
    Fine-tunes a language model using the LoRA (Low-Rank Adaptation) technique.
    """
    dataset = load_dataset(args.dataset, split="train")    
    try:
        xm.master_print("Load model and tokenizer locally...")
        tokenizer = AutoTokenizer.from_pretrained(args.tokenizer_path)
        tokenizer.pad_token = tokenizer.eos_token
        with lazy_load_for_parallelism(tensor_parallel_size=args.tp_size):
            model = AutoModelForCausalLM.from_pretrained(
                args.model_path, 
                low_cpu_mem_usage=True, 
                torch_dtype=torch.bfloat16 if args.bf16 else torch.float32
            )
    except Exception as e:
        print(f"Error loading model or tokenizer: {e}")
        raise
    
    lora_config = LoraConfig(
        r=16,
        lora_alpha=16,
        lora_dropout=0.05,
        target_modules=["q_proj", "v_proj"],# ["o_proj", "k_proj", "up_proj", "down_proj"],
        bias="none",
        task_type="CAUSAL_LM",
    )
    
    xm.master_print(lora_config)
    
    training_args = NeuronSFTConfig(
        output_dir=args.model_checkpoint_path,
        overwrite_output_dir=True,
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.train_batch_size,
        gradient_accumulation_steps=args.gradient_accumulation_steps,
        learning_rate=args.learning_rate,
        weight_decay=args.weight_decay,
        warmup_steps=args.warmup_steps,
        bf16=args.bf16,
        tensor_parallel_size=args.tp_size,
        pipeline_parallel_size=args.pp_size,
        save_steps=args.checkpoint_frequency,
        logging_steps=100,
        max_steps=args.max_steps,
        max_seq_length=args.max_seq_length,
        )
    xm.master_print(f"training_args: {training_args}")

    trainer = NeuronSFTTrainer(
        args=training_args,
        model=model,
        peft_config=lora_config,
        tokenizer=tokenizer,
        train_dataset=dataset,
        formatting_func=format_dolly,
    )

    trainer.train()
    trainer.save_model(args.model_final_path)
    
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model_path", type=str)
    parser.add_argument("--tokenizer_path", type=str)
    parser.add_argument("--epochs", type=int)
    parser.add_argument("--train_batch_size", type=int)
    parser.add_argument("--learning_rate", type=float)
    parser.add_argument("--weight_decay", type=float)
    parser.add_argument("--bf16", type=bool)
    parser.add_argument("--tp_size", type=int)
    parser.add_argument("--pp_size", type=int)
    parser.add_argument("--gradient_accumulation_steps", type=int)
    parser.add_argument("--warmup_steps", type=int)
    parser.add_argument("--early_stopping_patience", type=int)
    parser.add_argument("--checkpoint_frequency", type=int)
    parser.add_argument("--dataset", type=str)
    parser.add_argument("--max_steps", type=int)
    parser.add_argument("--max_seq_length", type=int)
    parser.add_argument("--model_type", type=str)
    parser.add_argument("--seed", type=str)
    parser.add_argument("--model_checkpoint_path", type=str)
    parser.add_argument("--model_final_path", type=str)
    args = parser.parse_args()
    
    set_seed(int(args.seed))
    training_function(args)
    