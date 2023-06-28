build:
	docker build -t nemomegatron-lm . 
	-rm /admin/ubuntu/megatron-lm/megatron-lm.sqsh
	enroot import -o /admin/ubuntu/megatron-lm/megatron-lm.sqsh dockerd://megatron-lm:latest

run:
	sbatch gpt.sbatch
