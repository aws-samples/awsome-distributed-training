FROM mosaicml/llm-foundry:2.3.1_cu121_aws-latest
COPY requirements.txt requirements.txt
RUN pip install -r requirements.txt