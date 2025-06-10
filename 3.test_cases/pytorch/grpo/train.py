import argparse
import os
import re
from datasets import load_dataset
from trl import GRPOConfig, GRPOTrainer
from math_verify import parse, verify
from datetime import datetime
import accelerate


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--vllm_server_host", type=str, default="", help="The server IP"
    )
    parser.add_argument(
        "--model",
        type=str,
        default="Qwen/Qwen2.5-0.5B-Instruct",
        help="The model to use",
    )
    args = parser.parse_args()

    dataset_id = "PrimeIntellect/verifiable-math-problems"
    dataset = load_dataset(dataset_id, split="train")

    dataset = dataset.train_test_split(test_size=0.1, seed=42)
    train_dataset = dataset["train"]
    test_dataset = dataset["test"]

    SYSTEM_PROMPT = (
        "A conversation between User and Assistant. The user asks a question, and the Assistant solves it. The assistant "
        "first thinks about the reasoning process in the mind and then provides the user with the answer. The reasoning "
        "process and answer are enclosed within <think> </think> and <answer> </answer> tags, respectively, i.e., "
        "<think>reasoning process here</think><answer>answer here</answer>"
    )

    ending = "Return your final response as 'Final Answer: \\boxed{<answer>}', where <answer> is the number or mathematical expression of the solution."

    def make_conversation(example):
        return {
            "prompt": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": example["prompt"][: -len(ending)].strip()},
            ],
        }

    train_dataset = train_dataset.map(make_conversation)

    # def format_reward(completions, **kwargs):
    #     pattern = r"^<think>(.*?)</think>\s*<answer>(.*?)</answer>$"
    #     rewards = []
    #     for completion in completions:
    #         match = re.search(pattern, completion[0]["content"], re.DOTALL)
    #         if match:
    #             # think_content = match.group(1).strip()
    #             # answer_content = match.group(2).strip()
    #             # if len(think_content) > len(answer_content) > 0:
    #             #     rewards.append(1.0)
    #             # else:
    #             #     rewards.append(0.5)
    #             rewards.append(1.0)
    #         else:
    #             rewards.append(0.0)
    #     return rewards

    def simple_format_reward(completions, **kwargs):
        completion_contents = [completion[0]["content"] for completion in completions]
        rewards = []
        for content in completion_contents:
            reward = 0.0
            if "<think>" in content:
                reward += 0.25
            if "</think>" in content:
                reward += 0.25
            if "<answer>" in content:
                reward += 0.25
            if "</answer>" in content:
                reward += 0.25
            rewards.append(reward)
        return rewards

    def format_reward(completions, **kwargs):
        """Reward function that checks if the reasoning process is enclosed within <think> and </think> tags, while the final answer is enclosed within <answer> and </answer> tags."""
        pattern = r"^<think>(.*?)</think>\s*<answer>(.*?)</answer>$"
        completion_contents = [completion[0]["content"] for completion in completions]
        matches = [
            re.match(pattern, content, re.DOTALL) for content in completion_contents
        ]
        return [1.0 if match else 0.0 for match in matches]

    def accuracy_reward(completions, **kwargs):
        """Reward function that checks if the completion is the same as the ground truth."""
        solutions = kwargs["gold_standard_solution"]
        completion_contents = [completion[0]["content"] for completion in completions]
        rewards = []
        for content, solution in zip(completion_contents, solutions):
            gold_parsed = parse(solution)
            if len(gold_parsed) != 0:
                answer_parsed = parse(content)
                if verify(gold_parsed, answer_parsed):
                    rewards.append(1.0)
                else:
                    rewards.append(0.0)
            else:
                rewards.append(None)
        return rewards

    def len_reward(completions, **kwargs):
        """Compute length-based rewards to discourage overthinking and promote token efficiency.

        Taken from the Kimi 1.5 tech report: https://arxiv.org/abs/2501.12599

        Args:
            completions: List of model completions
            solution: List of ground truth solutions

        Returns:
            List of rewards where:
            - For correct answers: reward = 0.5 - (len - min_len)/(max_len - min_len)
            - For incorrect answers: reward = min(0, 0.5 - (len - min_len)/(max_len - min_len))
        """
        solution = kwargs["gold_standard_solution"]
        contents = [completion[0]["content"] for completion in completions]

        # First check correctness of answers
        correctness = []
        for content, sol in zip(contents, solution):
            gold_parsed = parse(sol)
            if len(gold_parsed) == 0:
                # Skip unparseable examples
                correctness.append(True)  # Treat as correct to avoid penalizing
                print("Failed to parse gold solution: ", sol)
                continue

            answer_parsed = parse(content)
            correctness.append(verify(answer_parsed, gold_parsed))

        # Calculate lengths
        lengths = [len(content) for content in contents]
        min_len = min(lengths)
        max_len = max(lengths)

        # If all responses have the same length, return zero rewards
        if max_len == min_len:
            return [0.0] * len(completions)

        rewards = []
        for length, is_correct in zip(lengths, correctness):
            lambda_val = 0.5 - (length - min_len) / (max_len - min_len)

            if is_correct:
                reward = lambda_val
            else:
                reward = min(0, lambda_val)

            rewards.append(float(reward))

        return rewards

    parent_dir = os.path.dirname(__file__)
    date_time_dir = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    output_dir = os.path.join(parent_dir, date_time_dir, args.model + "-GRPO")
    output_dir_list = [output_dir]
    accelerate.utils.broadcast_object_list(output_dir_list)
    output_dir = output_dir_list[0]
    assert output_dir is not None

    training_args = GRPOConfig(
        output_dir=output_dir,
        learning_rate=1e-5,
        remove_unused_columns=False,
        num_train_epochs=1,
        per_device_train_batch_size=96,  # 96 for 14B, 32 for 72B
        bf16=True,
        gradient_checkpointing=True,
        logging_steps=10,
        report_to="wandb",
        use_vllm=True,
        vllm_server_host=args.vllm_server_host,
        vllm_server_timeout=600,
        save_strategy="steps",
        save_steps=100,
        torch_empty_cache_steps=10,
        # Parameters related to evaluation
        # eval_strategy="steps",
        # eval_steps=1000,
        # eval_on_start=True,
    )

    trainer = GRPOTrainer(
        model=args.model,
        reward_funcs=[simple_format_reward, format_reward, accuracy_reward, len_reward],
        args=training_args,
        train_dataset=train_dataset,
        eval_dataset=test_dataset,
    )

    trainer.train()


if __name__ == "__main__":
    main()
