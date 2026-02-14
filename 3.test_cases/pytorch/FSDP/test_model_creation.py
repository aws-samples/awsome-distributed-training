#!/usr/bin/env python3
"""
Test script to verify model creation and basic functionality.
This tests the model configuration and instantiation without distributed training.
"""

import sys
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer

# Add src to path
sys.path.insert(0, '/Users/nchkumar/Code/smml-work/awsome-distributed-training/3.test_cases/pytorch/FSDP/src')

from model_utils.train_utils import get_model_config
from model_utils.arguments import parse_args

def test_model_config():
    """Test that model configuration can be created."""
    print("Testing model configuration creation...")
    
    # Simulate command line args for llama3_2_1b
    test_args = [
        '--model_type=llama_v3',
        '--max_context_width=128',  # Reduced for testing
        '--num_key_value_heads=2',
        '--intermediate_size=8192',
        '--hidden_width=2048',
        '--num_layers=16',
        '--num_heads=32',
        '--vocab_size=32000',
    ]
    
    # Parse args
    args, _ = parse_args()
    
    # Override args for testing
    args.model_type = 'llama_v3'
    args.max_context_width = 128
    args.num_key_value_heads = 2
    args.intermediate_size = 8192
    args.hidden_width = 2048
    args.num_layers = 2  # Reduced for faster testing
    args.num_heads = 32
    args.vocab_size = 32000
    
    # Get model config
    model_config = get_model_config(args)
    
    print(f"✓ Model config created successfully")
    print(f"  - Model type: {args.model_type}")
    print(f"  - Hidden size: {model_config.hidden_size}")
    print(f"  - Num layers: {model_config.num_hidden_layers}")
    print(f"  - Num heads: {model_config.num_attention_heads}")
    print(f"  - Vocab size: {model_config.vocab_size}")
    print(f"  - Max position embeddings: {model_config.max_position_embeddings}")
    
    return model_config, args

def test_model_instantiation(model_config):
    """Test that model can be instantiated."""
    print("\nTesting model instantiation...")
    
    try:
        # Create model on CPU
        model = AutoModelForCausalLM.from_config(model_config)
        
        # Count parameters
        num_params = sum(p.numel() for p in model.parameters())
        print(f"✓ Model instantiated successfully")
        print(f"  - Total parameters: {num_params:,} ({num_params * 1e-9:.2f}B)")
        
        # Test forward pass with dummy input
        dummy_input = torch.randint(0, model_config.vocab_size, (1, 10))
        with torch.no_grad():
            output = model(input_ids=dummy_input, labels=dummy_input)
        
        print(f"✓ Forward pass successful")
        print(f"  - Loss: {output.loss.item():.4f}")
        
        return model
        
    except Exception as e:
        print(f"✗ Model instantiation failed: {e}")
        raise

def test_tokenizer():
    """Test tokenizer loading."""
    print("\nTesting tokenizer...")
    
    try:
        tokenizer = AutoTokenizer.from_pretrained("hf-internal-testing/llama-tokenizer")
        print(f"✓ Tokenizer loaded successfully")
        print(f"  - Vocab size: {tokenizer.vocab_size}")
        
        # Test encoding/decoding
        text = "Hello, world!"
        tokens = tokenizer.encode(text)
        decoded = tokenizer.decode(tokens)
        print(f"  - Test encoding: '{text}' -> {tokens} -> '{decoded}'")
        
        return tokenizer
        
    except Exception as e:
        print(f"✗ Tokenizer loading failed: {e}")
        raise

def test_dataset_loading():
    """Test dataset loading."""
    print("\nTesting dataset loading...")
    
    try:
        from datasets import load_dataset
        
        # Load a small sample
        dataset = load_dataset("allenai/c4", "en", split="train", streaming=True)
        sample = next(iter(dataset))
        
        print(f"✓ Dataset loaded successfully")
        print(f"  - Sample text: {sample['text'][:100]}...")
        
        return dataset
        
    except Exception as e:
        print(f"✗ Dataset loading failed: {e}")
        raise

def main():
    """Run all tests."""
    print("=" * 60)
    print("PyTorch FSDP Training - Model Test Suite")
    print("=" * 60)
    
    try:
        # Test 1: Model config
        model_config, args = test_model_config()
        
        # Test 2: Model instantiation
        model = test_model_instantiation(model_config)
        
        # Test 3: Tokenizer
        tokenizer = test_tokenizer()
        
        # Test 4: Dataset
        dataset = test_dataset_loading()
        
        print("\n" + "=" * 60)
        print("✓ All tests passed successfully!")
        print("=" * 60)
        
        return 0
        
    except Exception as e:
        print("\n" + "=" * 60)
        print(f"✗ Test failed with error: {e}")
        print("=" * 60)
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
