#!/bin/bash

pcluster create-cluster --cluster-configuration pcluster-config.yaml --cluster-name pcluster-ml --region us-west-2 --suppress-validators "type:InstanceTypeBaseAMICompatibleValidator" --rollback-on-failure "false"
