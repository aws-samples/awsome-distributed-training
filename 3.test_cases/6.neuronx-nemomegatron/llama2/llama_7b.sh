#!/usr/bin/env bash

export SEQ_LENGTH=4096
export HS=4096
export TP=8
export PP=1
export N_LAYERS=32
export N_AH=32
export FFN_HS=11008
export GBS=256

# pushd .
# cd /usr/local/lib/python3.8/site-packages/nemo/collections/nlp/data/language_modeling/megatron/
# make
# popd

./test_llama.sh