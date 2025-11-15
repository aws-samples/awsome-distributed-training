# First, get the head pod name
export HEAD_POD=$(kubectl get pods --selector=ray.io/node-type=head -o custom-columns=POD:metadata.name --no-headers)

# Then run the commands
kubectl exec -it $HEAD_POD -- /bin/bash -c '
if [ ! -d "verl" ]; then
    git clone https://github.com/volcengine/verl
fi
cd verl && \
export VERL_HOME=/fsx/verl && \
export RAY_ADDRESS="http://localhost:8265" && \
export RAY_DATA_HOME="/fsx/verl" && \
export OVERWRITE=1 && \
bash recipe/dapo/prepare_dapo_data.sh
'