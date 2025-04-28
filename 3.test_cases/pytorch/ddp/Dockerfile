FROM pytorch/pytorch:latest

RUN apt update && apt upgrade -y

RUN mlflow==2.13.2 sagemaker-mlflow==0.1.0
COPY ddp.py /workspace

