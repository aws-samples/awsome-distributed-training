#!/bin/bash

EXPOSED=$(lsof -i :8266)
if [ "$?" == 0 ]; then
	echo "Ray is exposed on port 8266"
else
	PID_FILE="$HOME/port-forward.pid"
	# kubectl port-forward --address 0.0.0.0 service/raycluster-kuberay-head-svc 8265:8265 > /dev/null 2>&1 &
	export SERVICEHEAD=$(kubectl get service | grep head-svc | awk '{print $1}' | head -n 1)

	kubectl port-forward --address 0.0.0.0 service/${SERVICEHEAD} 8266:8265 > /dev/null 2>&1 &
	echo $! > "$PID_FILE"
	echo "Port-forward started, PID $! saved in $PID_FILE"
	sleep 1
	echo "Port forwarded, visit http://localhost:8266"
fi