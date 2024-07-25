#!/bin/bash

# mc --> Multiverse Coomputing CompactifAI
# Website: https://multiversecomputing.com/
# Paper: https://multiversecomputing.com/papers
# CompactifAI: Extreme Compression of Large Language Models using Quantum-Inspired Tensor Networks
# https://arxiv.org/abs/2401.14109

dep_cmds="wget curl jq"
hf_token_read="hf_" # WARNING TO REMOVE !!!
mc_token=""  # WARNING TO REMOVE !!!
mc_url="https://compactifai.singularity-quantum.com"
waiting=30

# TODO list of parameters
# compression_levels="small"
# compressions="0"
# self_attns="0.2"

# tmp="$(mktemp)"
tmp="temp.json"

mcget(){
  echo "API GET $1" >&2
  curl -s -X 'GET' \
  "${mc_url}${1}" \
  -H 'accept: application/json' \
  -H "Authorization: ${mc_token}" \
  | jq
}

mcput(){
  echo "API POST $1" >&2
  curl -s -X 'POST' \
    "${mc_url}${1}" \
    -H 'accept: application/json' \
    -H "Authorization: ${mc_token}" \
    -H 'Content-Type: application/json' \
    -d "${2}" \
    | jq
}    

mcjobwait(){
  # expect "Succeeded"
  while [[ $(mcget /jobs/${1}/status 2>/dev/null | jq -r '.status') == "pending" ]] ;do
    mcget /jobs/${1}/status
    echo "Waiting on job_id ${1} for ${waiting}s more..."
    sleep ${waiting}
  done
  mcget /jobs/${1}/status
}

mcjobwalk(){
  # mcget /jobs/${1}/status
  mcjobwait ${1}
  mcget /jobs/${1}/result
}

# check external dependencies
dep_check(){
    for c in ${@} ;do
        # $c --version | head -n1
        if ! command -v $c &> /dev/null ; then
            echo "[ERROR] Command \"${c}\" can not be found." >&2
        fi
    done
}

## API DOC ##
# from https://compactifai.singularity-quantum.com/docs

# Authentication
# GET /session/status # Returns the authentication status.
# Models
# GET /models/original # Returns the list of original models.
# GET /models/compressed # Returns the list of compressed models.
# GET /models/original/{model_id}/info # Returns information about an original model.
# GET /models/compressed/{model_id}/info # Returns information about a compressed model.
# GET /models/original/{model_id}/content # Returns a download link for the provided original model.
# GET /models/compressed/{model_id}/content # Returns a download link for the provided compressed model.
# POST /models/compressed/{model_id}/heal # Creates a healing request for a compressed model.
# POST /models/original/{model_id}/profile # Creates a profiling request.
# POST /models/original/{model_id}/compress # Creates a compression request.
# Jobs
# GET /jobs/{job_id}/status # Returns the status of the job.
# GET /jobs/{job_id}/result # Returns the result of the job.

## EXEC ##

dep_check $dep_cmds

mcget /session/status
# {
#   "result": true
# }

mcget /models/original | tee "${tmp}"
declare -A models_original
while IFS="=" read -r mi mn ; do
  models_original[${mi}]="${mn}"
done < <(jq -r 'map("\(.model_id)=\(.model_name)")|.[]' "${tmp}")
# [
#   {
#     "model_id": "2eda702b-5d9c-4beb-ae9a-0af5f79c1774",
#     "model_name": "llama_7b"
#   },
#   {
#     "model_id": "81913e3e-7b1f-40cc-8f27-0883698bd493",
#     "model_name": "mixtral_8x7b"
#   }
# ]

# "mixtral_8x7b" not available yet
# for model_id in ${!models_original[@]} ;do
#   model_name=${models_original[${model_id}]}
#   echo "Using model_name=${model_name} model_id=${model_id}"

model_id="2eda702b-5d9c-4beb-ae9a-0af5f79c1774"
model_name="llama_7b"

mcget /models/original/${model_id}/info | tee "model_original_${model_name}_${model_id}_info.json"
# {
#   "id": "2eda702b-5d9c-4beb-ae9a-0af5f79c1774",
#   "name": "llama_7b",
#   "size_in_bytes": 26955565126,
#   "num_params": 6740000000,
#   "num_blocks": 32,
#   "layers": [
#     "model.layers[0].self_attn.q_proj",
# ...
#             }
#           }
#         }
#       },
#       "username": "amal.missaoui"
#     }
#   ]
# }

# small medium full (32 blocks, small=1st block, medium=3, full=all blocks)
# for compression_level in compression_levels ;do
mcput /models/original/${model_id}/profile \
'{
    "compressions": [
      0.2
    ],
    "compression_level": "small"
}' \
| tee "${tmp}"
job_id="$(jq -r '.job_id' "${tmp}")"

# 96c6351f-2b5d-4360-8f30-1f46d7476010

# {
#   "job_id": "b10c2aa5-5ff5-49ae-a089-049a9b370b08"
# }
# job_id="b10c2aa5-5ff5-49ae-a089-049a9b370b08"

# {
#   "job_id": "7ce29c8c-7730-4849-ace2-e4d93923c97f"
# }
# job_id="7ce29c8c-7730-4849-ace2-e4d93923c97f"

mcjobwalk ${job_id}
# mcget /jobs/${job_id}/status
# {
#   "status": "pending",
#   "error_msg": null
# }

# mcjobwait ${job_id}

# mcget /jobs/${job_id}/result
# {
#   "error_msg": "Not available"
# }

mcget /models/original/${model_id}/info | tee "model_original_${model_name}_${model_id}_profiled_info.json"
# mcget /models/original/${model_id}/info | grep -i result
#       "profiling_result": null,
#       "profiling_result": null,
#       "profiling_result": {
#       "profiling_result": {
#       "profiling_result": {
#       "profiling_result": {
#       "profiling_result": {
#       "profiling_result": {
#       "profiling_result": {
#       "profiling_result": {
# mcget /models/original/${model_id}/info | grep -i username
#       "username": "gmangeot@amazon.com"
#       "username": "gmangeot@amazon.com"
#       "username": null
#       "username": null
#       "username": null
#       "username": null
#       "username": null
#       "username": "amal.missaoui"
#       "username": "amal.missaoui"
#       "username": "amal.missaoui"
#  mcget /models/original/${model_id}/info | grep -i size
#   "size_in_bytes": 26955565126,

      # "profiling_result": {
      #   "0.2": {
      #     "model.layers[0].self_attn": {
      #       "model.layers[0].self_attn.q_proj": {
      #         "average_cosin_sim": 0.9999659842763795
      #       },
      #       "model.layers[0].self_attn.k_proj": {
      #         "average_cosin_sim": 0.9998973543877284
      #       },
      #       "model.layers[0].self_attn.v_proj": {
      #         "average_cosin_sim": 0.994437344715757
      #       },
      #       "model.layers[0].self_attn.o_proj": {
      #         "average_cosin_sim": 0.9958028982754699
      #       }
      #     },
      #     "model.layers[7].mlp": {
      #       "model.layers[7].mlp.gate_proj": {
      #         "average_cosin_sim": 0.9986901569572959
      #       },
      #       "model.layers[7].mlp.up_proj": {
      #         "average_cosin_sim": 0.9985359930712987
      #       },
      #       "model.layers[7].mlp.down_proj": {
      #         "average_cosin_sim": 0.9886690876250217
      #       }
      #     },
      #     "lm_head": {
      #       "lm_head": {
      #         "average_cosin_sim": 0.9999999576261298
      #       }
      #     }
      #   }

# for self_attn in self_attns ;do
# layers[i] is block i ; i: 0-31
# Meta convention for llama
mcput /models/original/${model_id}/compress \
'{
"compression_levels": {
"model.layers[0].self_attn.o_proj": "0.2",
"model.layers[0].self_attn.v_proj": "0.2"
}
}' \
| tee "${tmp}"
job_id="$(jq -r '.job_id' "${tmp}")"

# {
#   "job_id": "bbca914a-8425-426e-bf86-db6fe59d211e"
# }
# job_id="bbca914a-8425-426e-bf86-db6fe59d211e"

# mcput /models/original/${model_id}/compress \
# '{
#   "compression_levels": {
#     "additionalProp1": 0,
#     "additionalProp2": 0,
#     "additionalProp3": 0
#   }
# }'
# {
#   "error_msg": "Layer additionalProp1 not found in model"
# }

mcjobwalk ${job_id}
# mcget /jobs/${job_id}/status
# {
#   "status": "pending",
#   "error_msg": null
# }

# mcjobwait ${job_id}

# mcget /jobs/${job_id}/result
# {
#   "error_msg": "Not available"
# }

# WARNING
compressed_model_id=$(mcget /jobs/${job_id}/result | jq -r 'result.compressed_model_id')
# compressed_model_id="2c7901b2-4133-4fa5-b71e-858af95fdbb1"
echo "Using compressed_model_id=${compressed_model_id}"

echo "List all compressed_model_id available:"
mcget /models/compressed | tee "models_compressed.json"
# [
#   {
#     "model_id": "2c7901b2-4133-4fa5-b71e-858af95fdbb1",
#     "original_model_name": "llama_7b",
#     "original_model_id": "2eda702b-5d9c-4beb-ae9a-0af5f79c1774",
#     "previous_model_id": null
#   },
# ...
#   {
#     "model_id": "25471765-ed54-4b91-9c32-091da81b768a",
#     "original_model_name": "llama_7b",
#     "original_model_id": "2eda702b-5d9c-4beb-ae9a-0af5f79c1774",
#     "previous_model_id": "f3828428-2ce0-4fa7-a847-9a6061c55a1f"
#   },
#   {
#     "model_id": "1f1fc3fb-c73d-47d8-9231-7cd3221901d9",
#     "original_model_name": "llama_7b",
#     "original_model_id": "2eda702b-5d9c-4beb-ae9a-0af5f79c1774",
#     "previous_model_id": "bf008b79-a2ac-4ca0-a303-96f632d31b1c"
#   },
# ...
#   {
#     "model_id": "db5828b8-17f4-4969-9bf1-50b9b8144efa",
#     "original_model_name": "llama_7b",
#     "original_model_id": "2eda702b-5d9c-4beb-ae9a-0af5f79c1774",
#     "previous_model_id": null
#   }
# ]

# PS: `previous_model_id` exists only if the compressed model was healed, if
# not the value of `previous_model_id`is null

mcget /models/compressed/${compressed_model_id}/info | tee "model_compressed_${model_name}_${model_id}_${compressed_model_id}_info-preheal.json"
# {
#   "id": "2c7901b2-4133-4fa5-b71e-858af95fdbb1",
#   "original_model_id": "2eda702b-5d9c-4beb-ae9a-0af5f79c1774",
#   "previous_compressed_model_id": null,
#   "size_reduction_ratio": 0.5018326903839367,
#   "parameters_reduction_ratio": 0.003736503272403713,
#   "healing_result": null,
#   "size_in_bytes": 13428381358,
#   "num_params": 6713237504,
#   "num_blocks": 32,
#   "layers": [
#     "model.embed_tokens.weight",
#     "model.layers.0.self_attn.q_proj.weight",
#     "model.layers.0.self_attn.k_proj.weight",
# ...
#     "model.layers.31.mlp.down_proj.weight",
#     "model.layers.31.input_layernorm.weight",
#     "model.layers.31.post_attention_layernorm.weight",
#     "model.norm.weight",
#     "lm_head.weight"
#   ]
# }

mcget /models/compressed/${compressed_model_id}/content | tee "${tmp}"
# {
#   "presigned_url": "https......"
# }
# PS: The link provided here will only stay valid for 1 hour and then it will expire
wget -O models/"model_compressed_${model_name}_${model_id}_${compressed_model_id}.zip" "$(jq -r '.presigned_url' "${tmp}")"
# 12.51G  29.3MB/s    in 8m 12s  
# 2024-07-16 17:28:54 (26.0 MB/s) - ‘2c7901b2-4133-4fa5-b71e-858af95fdbb1_compressed_model.bin’ saved [13428381358/13428381358]

# echo "Size ratio: $()"
# echo "26955565126/13428381358" | bc -l 
# 2.00735773041932102685
# 32 -> float16

mcget /models/compressed/${compressed_model_id}/heal | tee "${tmp}"
job_id="$(jq -r '.job_id' "${tmp}")"
# {
#   "detail": "Method Not Allowed"
# }
# ERROR OR WARNING DIDNT GET ANY JOB HERE

mcjobwalk ${job_id}

mcget /models/compressed/${compressed_model_id}/info | tee "model_compressed_${model_name}_${model_id}_${compressed_model_id}_info-postheal.json"
# {
#   "id": "2c7901b2-4133-4fa5-b71e-858af95fdbb1",
#   "original_model_id": "2eda702b-5d9c-4beb-ae9a-0af5f79c1774",
#   "previous_compressed_model_id": null,
#   "size_reduction_ratio": 0.5018326903839367,
#   "parameters_reduction_ratio": 0.003736503272403713,
#   "healing_result": null,
#   "size_in_bytes": 13428381358,
#   "num_params": 6713237504,
#   "num_blocks": 32,
#   "layers": [
#     "model.embed_tokens.weight",
#     "model.layers.0.self_attn.q_proj.weight",
#     "model.layers.0.self_attn.k_proj.weight",
#     "model.layers.0.self_attn.v_proj.ttensor_0",
# ...
#     "model.layers.31.post_attention_layernorm.weight",
#     "model.norm.weight",
#     "lm_head.weight"
#   ]
# }

diff "model_compressed_${model_name}_${model_id}_${compressed_model_id}_info-preheal.json" "model_compressed_${model_name}_${model_id}_${compressed_model_id}_info-postheal.json"
# same same


mcget /models/custom # to list the custom models available
# [
#   "super_pintxo"
# ]
mcget /models/custom/super_pintxo/content  | tee "${tmp}"
# {
#   "presigned_url": "https://multiverse-compactifai-prod-io-bucket.s3.amazonaws.com/custom_models/super_pintxo.zip?AWSAccessKeyId=ASIA..."
# }
wget -O models/super_pintxo.zip "$(jq -r '.presigned_url' "${tmp}")"


# done # self_attns
# done # compressions
# done # compression_levels
# done # original models
rm -f "${tmp}"


python3 -m venv venv && source venv/bin/activate
python3 -m pip install torch torchvision transformers datasets typing tqdm
python3 -m joinem # parquet merging for OSCAR-2301-Hindi-Cleaned-3.0.parquet

# python train_model.py --model_path models/llama_compres --dataset_path datasets/OSCAR-
# 2301-Hindi-Cleaned-3.0.parquet --output_dir ./results --num_train_epochs 3 --
# per_device_train_batch_size 4 --per_device_eval_batch_size 4 --save_steps 10000 --
# save_total_limit 2 --logging_dir ./logs --max_length 1024 --trained_model_dir
# ./trained_model

### Explanation of Parameters:
# - --model_path : Path to the HuggingFace model to be trained.
# - --dataset_path : Path to the dataset file in parquet format.
# - --output_dir : Directory where the training results will be saved.
# - --num_train_epochs : Number of training epochs.
# - --per_device_train_batch_size : Training batch size per device.
# - --per_device_eval_batch_size : Evaluation batch size per device.
# - --save_steps : Number of steps before saving the model.
# - --save_total_limit : Maximum number of saved checkpoints.
# - --logging_dir : Directory for logging training metrics.
# - --max_length : Maximum sequence length.
# - --trained_model_dir : Directory where the trained model will be saved.

# parser = argparse.ArgumentParser(description="Train a language model using a pretrained  model.")
# parser.add_argument("--model_path", type=str, required=True, help="Path to the pretrained model and tokenizer.")
# parser.add_argument("--dataset_path", type=str, required=True, help="Path to the parquet dataset file.")
# parser.add_argument("--output_dir", type=str, default="./results", help="Directory to save the training results.")
# parser.add_argument("--num_train_epochs", type=int, default=3, help="Number of training epochs.")
# parser.add_argument("--per_device_train_batch_size", type=int, default=4, help="Batch size for training.")
# parser.add_argument("--per_device_eval_batch_size", type=int, default=4, help="Batch size for evaluation.")
# parser.add_argument("--save_steps", type=int, default=10000, help="Number of steps between model saves.")
# parser.add_argument("--save_total_limit", type=int, default=2, help="Maximum number of saved model checkpoints.")
# parser.add_argument("--logging_dir", type=str, default='./logs', help="Directory for training logs.")
# parser.add_argument("--max_length", type=int, default=1024, help="Maximum sequence length for tokenization.")
# parser.add_argument("--trained_model_dir", type=str, default="./trained_model", help="Directory to save the trained model and tokenizer.")

cd datasets
for i in {0..9} ;do
  wget -c --header="Authorization: Bearer ${hf_token_read}" \
    "https://huggingface.co/datasets/oscar-corpus/OSCAR-2301/resolve/refs%2Fconvert%2Fparquet/hi/partial-train/000${i}.parquet" &
done
wait
ls -1 *.parquet | python3 -m joinem hf-oscar-2301-partial-train-0-9.parquet
cd -
ls -lh datasets/
# total 3.0G
# -rw-r--r-- 1 gmangeot clusteradmins 187M Jul 12  2023 0000.parquet
# -rw-r--r-- 1 gmangeot clusteradmins 188M Jul 12  2023 0001.parquet
# -rw-r--r-- 1 gmangeot clusteradmins 187M Jul 12  2023 0002.parquet
# -rw-r--r-- 1 gmangeot clusteradmins 187M Jul 12  2023 0003.parquet
# -rw-r--r-- 1 gmangeot clusteradmins 187M Jul 12  2023 0004.parquet
# -rw-r--r-- 1 gmangeot clusteradmins 187M Jul 12  2023 0005.parquet
# -rw-r--r-- 1 gmangeot clusteradmins 188M Jul 12  2023 0006.parquet
# -rw-r--r-- 1 gmangeot clusteradmins 187M Jul 12  2023 0007.parquet
# -rw-r--r-- 1 gmangeot clusteradmins 186M Jul 12  2023 0008.parquet
# -rw-r--r-- 1 gmangeot clusteradmins 179M Jul 12  2023 0009.parquet
# -rw-r--r-- 1 gmangeot clusteradmins 1.2G Jul 16 23:01 hf-oscar-2301-partial-train-0-9.parquet

cd models/
mv "model_compressed_${model_name}_${model_id}_${compressed_model_id}.zip" 
unzip 2c7901b2-4133-4fa5-b71e-858af95fdbb1_compressed_model.zip 
# Archive:  2c7901b2-4133-4fa5-b71e-858af95fdbb1_compressed_model.zip
#  extracting: tokenizer_config.json   
#  extracting: tokenizer.json          
#  extracting: model-00002-of-00003.safetensors  
#  extracting: generation_config.json  
#  extracting: model-00001-of-00003.safetensors  
#  extracting: model-00003-of-00003.safetensors  
#  extracting: special_tokens_map.json  
#  extracting: config.json             
#  extracting: model.safetensors.index.json 

# train_model.py
python trainer_script.py \
  --model_path models/"${compressed_model_id}_${compressed_model}" \
  --dataset_path datasets/OSCAR-2301-Hindi-Cleaned-3.0.parquet \
  --output_dir ./results --num_train_epochs 3 \
  --per_device_train_batch_size 4 \
  --per_device_eval_batch_size 4 \
  --save_steps 10000 \
  --save_total_limit 2 \
  --logging_dir ./logs \
  --max_length 1024 \
  --trained_model_dir ./trained_model



python trainer_script.py \
  --model_path models/2c7901b2-4133-4fa5-b71e-858af95fdbb1_compressed_model.bin \
  --dataset_path datasets/hf-oscar-2301-partial-train-0-9.parquet \
  --output_dir ./results --num_train_epochs 3 \
  --per_device_train_batch_size 4 \
  --per_device_eval_batch_size 4 \
  --save_steps 10000 \
  --save_total_limit 2 \
  --logging_dir ./logs \
  --max_length 1024 \
  --trained_model_dir ./trained_model

python trainer_script.py \
  --model_path models/mymodel \
  --dataset_path datasets/hf-oscar-2301-partial-train-0-9.parquet \
  --output_dir ./results --num_train_epochs 3 \
  --per_device_train_batch_size 4 \
  --per_device_eval_batch_size 4 \
  --save_steps 10000 \
  --save_total_limit 2 \
  --logging_dir ./logs \
  --max_length 1024 \
  --trained_model_dir ./trained_model






exit
