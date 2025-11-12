#!/usr/bin/env python3
"""
Test vLLM with a small language model
"""
import sys
from vllm import LLM, SamplingParams

def test_vllm(model_name="facebook/opt-125m", max_tokens=50):
    """Test vLLM with a small model"""

    print(f"=" * 80)
    print(f"Testing vLLM with {model_name}")
    print(f"=" * 80)

    # Initialize model
    print(f"\n1. Loading model: {model_name}")
    llm = LLM(
        model=model_name,
        max_model_len=512,  # Small context for testing
        gpu_memory_utilization=0.5,  # Use 50% GPU memory
        enforce_eager=True,  # Disable CUDA graph for testing
    )
    print(f"✅ Model loaded successfully")

    # Create sampling parameters
    sampling_params = SamplingParams(
        temperature=0.8,
        top_p=0.95,
        max_tokens=max_tokens
    )

    # Test prompts
    prompts = [
        "Hello, my name is",
        "The capital of France is",
        "In a galaxy far far away,",
    ]

    print(f"\n2. Running inference on {len(prompts)} prompts...")
    outputs = llm.generate(prompts, sampling_params)

    # Print results
    print(f"\n3. Results:")
    print("=" * 80)
    for output in outputs:
        prompt = output.prompt
        generated_text = output.outputs[0].text
        print(f"\nPrompt: {prompt}")
        print(f"Generated: {generated_text}")
        print("-" * 80)

    print(f"\n✅ vLLM test completed successfully!")
    print(f"=" * 80)

if __name__ == "__main__":
    # Use model from command line or default
    model = sys.argv[1] if len(sys.argv) > 1 else "facebook/opt-125m"
    test_vllm(model)
