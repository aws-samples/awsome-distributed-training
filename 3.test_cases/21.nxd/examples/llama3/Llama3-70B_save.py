from transformers import AutoTokenizer, AutoModelForCausalLM
import torch

#model = AutoModelForCausalLM.from_pretrained("meta-llama/Meta-Llama-3-70B")
model = AutoModelForCausalLM.from_pretrained("./Meta-Llama-3-70B")

torch.save(model.state_dict(), '/fsx/llama-3-70b.pt')