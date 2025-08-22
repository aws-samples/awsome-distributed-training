# makefile for manual installation for development (will be deleted eventually)
# run these commands on the head node

NUM_WORKERS ?= 2

install-all: install-head install-workers

install-head:
	sudo python3 install_observability.py --node-type controller --region us-west-2 --prometheus-remote-write-url https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-e37c0ee4-7f7f-4f65-b72b-5455852d0c23/api/v1/remote_write

install-workers:
	srun -N $(NUM_WORKERS) sudo python3 install_observability.py --node-type compute --region us-west-2 --prometheus-remote-write-url https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-e37c0ee4-7f7f-4f65-b72b-5455852d0c23/api/v1/remote_write


stop-all: stop-head stop-workers

stop-head:
	sudo python3 stop_observability.py --node-type controller

stop-workers:
	srun -N $(NUM_WORKERS) sudo python3 stop_observability.py --node-type compute

status:
	docker ps --no-trunc
	srun -N $(NUM_WORKERS) docker ps --no-trunc

