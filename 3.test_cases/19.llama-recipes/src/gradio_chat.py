import argparse
import json

import gradio as gr
from openai import OpenAI
import requests

host = "localhost"
model = None
messages=[
    {"role": "system", "content": "You are a helpful assistant."},
]

def http_bot(prompt):
    global host, model, messages
    headers = {"User-Agent": "vLLM Client"}
    # Set OpenAI's API key and API base to use vLLM's API server.
    openai_api_key = "EMPTY"
    openai_api_base = f"http://{host}:8000/v1"

    client = OpenAI(
        api_key=openai_api_key,
        base_url=openai_api_base,
    )
    messages.append({"role": "user", "content": prompt})
    chat_response = client.chat.completions.create(
        model=model, messages=messages
    )
    print("Chat response:", chat_response)
    print(chat_response.__dict__)
    messages.append({"role": "assistant", "content": chat_response.choices[0].message.content})
    print(messages)
    yield chat_response.choices[0].message.content


def build_demo():
    with gr.Blocks() as demo:
        gr.Markdown("# vLLM text completion demo\n")
        inputbox = gr.Textbox(label="Input",
                              placeholder="Enter text and press ENTER")
        outputbox = gr.Textbox(label="Output",
                               placeholder="Generated result from the model")
        inputbox.submit(http_bot, [inputbox], [outputbox])
    return demo


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", type=str, default=None)
    parser.add_argument("--model", type=str, default=None)
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    host = args.host
    model = args.model

    demo = build_demo()
    demo.queue().launch(server_name="0.0.0.0",
                        server_port=args.port,
                        share=True)