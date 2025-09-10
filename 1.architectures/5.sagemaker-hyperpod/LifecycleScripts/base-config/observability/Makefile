# makefile for manual installation for development (will be deleted eventually)
# run these commands on the head node

NUM_WORKERS ?= 5
PROMETHEUS_REMOTE_WRITE_URL ?= https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-1143f100-e177-4eda-9269-2a1da719c1db/api/v1/remote_write
ADVANCED ?= 0

ifeq ($(ADVANCED),1)
	ARG_ADVANCED = --advanced
else
	ARG_ADVANCED = 
endif


install-all: install-head install-workers

install-head:
	sudo python3 install_observability.py --node-type controller --prometheus-remote-write-url $(PROMETHEUS_REMOTE_WRITE_URL) $(ARG_ADVANCED)

install-workers:
	srun -N $(NUM_WORKERS) sudo python3 install_observability.py --node-type compute --prometheus-remote-write-url $(PROMETHEUS_REMOTE_WRITE_URL) $(ARG_ADVANCED)


stop-all: stop-head stop-workers

stop-head:
	sudo python3 stop_observability.py --node-type controller

stop-workers:
	srun -N $(NUM_WORKERS) sudo python3 stop_observability.py --node-type compute

status:
	docker ps --no-trunc
	srun -N $(NUM_WORKERS) docker ps --no-trunc

clean:
	rm -f go1.22*
	sudo rm -rf slurm_exporter
