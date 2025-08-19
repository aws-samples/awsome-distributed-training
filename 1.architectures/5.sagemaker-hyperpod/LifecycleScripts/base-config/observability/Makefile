# makefile for manual installation for development (will be deleted eventually)

install-on-head:
	aaa

install-on-workers:
	srun -N 2 sudo bash ./install_node_exporter.sh
	srun -N 2 sudo bash ./install_dcgm_exporter.sh
	# srun -N 2 sudo bash ./install_efa_exporter.sh

stop-all:
	srun -N 2 docker stop node-exporter
	srun -N 2 docker stop dcgm-exporter
	srun -N 2 docker stop efa-exporter

