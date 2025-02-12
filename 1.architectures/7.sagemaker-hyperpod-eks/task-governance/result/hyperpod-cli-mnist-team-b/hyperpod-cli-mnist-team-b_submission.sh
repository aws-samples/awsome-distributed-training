#!/bin/bash
helm install --timeout=15m --wait  --namespace hyperpod-ns-team-b hyperpod-cli-mnist-team-b /Users/nadknish/repos/workshop-validation/awsome-distributed-training/1.architectures/7.sagemaker-hyperpod-eks/task-governance/result/hyperpod-cli-mnist-team-b/k8s_template
