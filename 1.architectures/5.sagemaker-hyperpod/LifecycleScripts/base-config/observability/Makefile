# makefile for manual installation for development (will be deleted eventually)
# run these commands on the head node

install-all: install-on-head install-on-workers

install-on-head:

	sudo mkdir -p /etc/otel
	sudo cp ./otel_config/config-head.yaml /etc/otel/config.yaml

	sudo bash ./install_node_exporter.sh
	sudo bash ./install_slurm_exporter.sh
	sudo bash ./install_otel_collector.sh

install-on-workers:

	srun -N 2 sudo mkdir -p /etc/otel
	srun -N 2 sudo cp ./otel_config/config-compute.yaml /etc/otel/config.yaml

	srun -N 2 sudo bash ./install_node_exporter.sh
	srun -N 2 sudo bash ./install_dcgm_exporter.sh
	srun -N 2 sudo bash ./install_efa_exporter.sh
	srun -N 2 sudo bash ./install_otel_collector.sh

status:
	docker ps
	srun -N 2 docker ps

stop-all:
	sudo systemctl stop prometheus-slurm-exporter
	docker stop node-exporter
	srun -N 2 docker stop node-exporter
	srun -N 2 docker stop dcgm-exporter
	srun -N 2 docker stop efa-exporter
	srun -N 2 docker stop otel-collector


