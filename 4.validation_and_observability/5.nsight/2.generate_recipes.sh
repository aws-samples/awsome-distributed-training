
#cuda_api_sum
/fsx/nsight-efa/target-linux-x64/nsys recipe cuda_api_sum --input nemotron_15B_bf16_16g_nvidia_config.nsys-rep

#cuda_api_sync
/fsx/nsight-efa/target-linux-x64/nsys recipe cuda_api_sync --input nemotron_15B_bf16_16g_nvidia_config.nsys-rep

/fsx/nsight-efa/target-linux-x64/nsys recipe cuda_gpu_kern_pace --input nemotron_15B_bf16_16g_nvidia_config.nsys-rep --name ncclDevKernel_ReduceScatter_Sum_f32_RING_LL

/fsx/nsight-efa/target-linux-x64/nsys recipe cuda_gpu_kern_pace --input nemotron_15B_bf16_16g_nvidia_config.nsys-rep --name ncclDevKernel_AllGather_RING_LL

/fsx/nsight-efa/target-linux-x64/nsys recipe cuda_gpu_kern_sum --input nemotron_15B_bf16_16g_nvidia_config.nsys-rep

/fsx/nsight-efa/target-linux-x64/nsys recipe cuda_gpu_mem_size_sum --input nemotron_15B_bf16_16g_nvidia_config.nsys-rep

/fsx/nsight-efa/target-linux-x64/nsys recipe cuda_gpu_mem_time_sum --input nemotron_15B_bf16_16g_nvidia_config.nsys-rep

/fsx/nsight-efa/target-linux-x64/nsys recipe cuda_gpu_time_util_map --input nemotron_15B_bf16_16g_nvidia_config.nsys-rep

/fsx/nsight-efa/target-linux-x64/nsys recipe nccl_sum --input nemotron_15B_bf16_16g_nvidia_config.nsys-rep

/fsx/nsight-efa/target-linux-x64/nsys recipe nccl_gpu_time_util_map --input nemotron_15B_bf16_16g_nvidia_config.nsys-rep