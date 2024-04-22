import gradio as gr
from transformers import AutoModelForCausalLM, AutoTokenizer


# Load the model and tokenizer
model_name = "meta-llama/Meta-Llama-3-70B"  # Replace with the actual model name
model = AutoModelForCausalLM.from_pretrained(model_name)
model = model.to("cuda")
tokenizer = AutoTokenizer.from_pretrained(model_name)

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
    
    return user_input

# Define a function to generate responses
def generate_response(user_input, chat_history=None):
    # Format the prompt as required by the model
    prompt = format_prompt(user_input, chat_history)
    
    # Generate a response
    inputs = tokenizer(prompt, return_tensors="pt")
    inputs = inputs.to("cuda")
    outputs = model.generate(**inputs)
    response = tokenizer.decode(outputs[0], skip_special_tokens=True)
    
    # Update chat history
    chat_history.append((user_input, response))
    
    return response

# Create the Gradio interface
iface = gr.Interface(
    fn=generate_response,
    inputs=["text"],
    outputs="text"
)

# Launch the interface
iface.launch(share=True)
