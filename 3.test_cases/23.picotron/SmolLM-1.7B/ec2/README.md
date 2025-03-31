## Running SmalLM-1.7B training on a single EC2 instance

The model is small enough to run on a single EC2 instance. 


```bash
# 3D Parallelism on CPU
docker run --rm -v /fsx:/fsx -w ${PWD} picotron \
    nsys profile  \
    --output ./nsight-report.nsys-rep \
    torchrun --nproc_per_node 8 ../../train.py \
    --config ../conf/llama-1B-cpu-dp2-tp2-pp2/config.json
```