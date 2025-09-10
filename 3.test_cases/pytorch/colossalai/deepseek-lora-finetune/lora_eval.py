import argparse
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, DynamicCache
from peft import PeftModel, LoraModel
from datasets import load_dataset
from coati.dataset.loader import apply_chat_template_and_mask
from typing import Optional
from math_verify import parse, verify
from tqdm import tqdm

# https://github.com/huggingface/transformers/issues/38710
class DynamicCacheWithGetMaxLength(DynamicCache):
    def get_max_length(self) -> Optional[int]:
        return self.get_max_cache_shape()

def eval(args):
    ######
    # How to Load lora Model
    ######
    # 1.Load base model
    base_model = AutoModelForCausalLM.from_pretrained(
        args.pretrained,
        torch_dtype=torch.bfloat16,
        device_map="auto",
        trust_remote_code=True
    )

    # 2.Load lora model
    if args.lora_adapter is not None:
        peft_model: LoraModel = PeftModel.from_pretrained(
            base_model,
            args.lora_adapter,
            torch_dtype=torch.bfloat16
        )

        # 3.Merge lora model
        merged_model = peft_model.merge_and_unload()
    else:
        merged_model = base_model

    # 4.Load tokenizer
    tokenizer = AutoTokenizer.from_pretrained(
        args.pretrained,
        trust_remote_code=True,
        pad_token="<|endoftext|>"
    )

    # 5.Save merged lora model
    if args.merged_model_path is not None:
        merged_model.save_pretrained(
            args.merged_model_path,
            safe_serialization=True
        )
        tokenizer.save_pretrained(args.merged_model_path)

    print(f"Load dataset: {args.dataset}")
    dataset = load_dataset(args.dataset, split=args.dataset_split)

    all = correct = 0
    for sample in tqdm(dataset):
        problem = sample["problem"]
        print(f"{problem=}")

        solution = sample["solution"]
        print(f"{solution=}")
        
        inputs = tokenizer.apply_chat_template([{"role": "user", "content": problem}], tokenize=True, return_dict=True, return_tensors="pt")
        inputs = inputs.to(merged_model.device)
        print(f"{inputs=}")

        outputs = merged_model.generate(**inputs, max_new_tokens=2048, past_key_values=DynamicCacheWithGetMaxLength())
        print(f"{outputs=}")

        completion = tokenizer.decode(outputs[0], skip_special_tokens=True)
        print(f"{completion=}")

        parsed_gold_solution = parse(solution)
        parsed_completion = parse(completion)
        result = verify(parsed_gold_solution, parsed_completion)
        print(f"{parsed_gold_solution=}")
        print(f"{parsed_completion=}")
        print(f"{result=}")
        all += 1
        if result:
            correct += 1
        print("="*100)

    print(f"{all=}")
    print(f"{correct=}")
    print(f"{correct/all=}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    # Basic evaluation information.
    parser.add_argument(
        "-m",
        "--pretrained",
        type=str,
        required=True,
        help="Path or name of the pre-trained model",
    )
    parser.add_argument(
        "--lora_adapter",
        type=str,
        required=False,
        help="Path of the LoRA adapter",
    )
    parser.add_argument(
        "--merged_model_path",
        type=str,
        required=False,
        help="Path to save the merged model",
    )
    parser.add_argument("-d", "--dataset", type=str, required=False, help="Dataset for training.")
    parser.add_argument("--dataset_split", type=str, default="test", help="Dataset split to use.")
    args = parser.parse_args()
    eval(args)
