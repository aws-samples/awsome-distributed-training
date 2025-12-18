#!/bin/bash
set -e

# Script to generate kustomization.yaml from env_vars file
# This replaces the envsubst workflow with kustomize-based configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_VARS_FILE="${SCRIPT_DIR}/env_vars"
KUSTOMIZATION_FILE="${SCRIPT_DIR}/kustomization.yaml"

# Check if env_vars file exists
if [ ! -f "${ENV_VARS_FILE}" ]; then
    echo "Error: ${ENV_VARS_FILE} not found."
    echo "Please copy setup/env_vars.example to setup/env_vars and configure it."
    exit 1
fi

# Source the env_vars file to get all variables
source "${ENV_VARS_FILE}"

# Ensure required variables are set
if [ -z "${REGISTRY}" ] || [ -z "${IMAGE}" ] || [ -z "${TAG}" ]; then
    echo "Error: REGISTRY, IMAGE, and TAG must be set in env_vars"
    exit 1
fi

# Construct the full image name
FULL_IMAGE="${REGISTRY}${IMAGE}:${TAG}"

# Generate kustomization.yaml with configMapGenerator and replacements
cat > "${KUSTOMIZATION_FILE}" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- raycluster.yaml

configMapGenerator:
- name: cluster-config
  literals:
  - INSTANCE_TYPE=${INSTANCE_TYPE}
  - IMAGE=${FULL_IMAGE}
  - HF_TOKEN=${HF_TOKEN}
  - NUM_NODES=${NUM_NODES}
  - NUM_GPU_PER_NODE=${NUM_GPU_PER_NODE}
  - NUM_EFA_PER_NODE=${NUM_EFA_PER_NODE}

replacements:
# Replace instance type in head and worker pods
- source:
    kind: ConfigMap
    name: cluster-config
    fieldPath: data.INSTANCE_TYPE
  targets:
  - select:
      kind: RayCluster
    fieldPaths:
    - spec.headGroupSpec.template.spec.nodeSelector.node\\.kubernetes\\.io/instance-type
    - spec.workerGroupSpecs.0.template.spec.nodeSelector.node\\.kubernetes\\.io/instance-type

# Replace image in head and worker pods
- source:
    kind: ConfigMap
    name: cluster-config
    fieldPath: data.IMAGE
  targets:
  - select:
      kind: RayCluster
    fieldPaths:
    - spec.headGroupSpec.template.spec.containers.0.image
    - spec.workerGroupSpecs.0.template.spec.containers.0.image

# Replace HF_TOKEN in head and worker pods
- source:
    kind: ConfigMap
    name: cluster-config
    fieldPath: data.HF_TOKEN
  targets:
  - select:
      kind: RayCluster
    fieldPaths:
    - spec.headGroupSpec.template.spec.containers.0.env.[name=HF_TOKEN].value
    - spec.workerGroupSpecs.0.template.spec.containers.0.env.[name=HF_TOKEN].value

# Replace number of nodes (replicas)
- source:
    kind: ConfigMap
    name: cluster-config
    fieldPath: data.NUM_NODES
  targets:
  - select:
      kind: RayCluster
    fieldPaths:
    - spec.workerGroupSpecs.0.replicas

# Replace num-gpus in rayStartParams
- source:
    kind: ConfigMap
    name: cluster-config
    fieldPath: data.NUM_GPU_PER_NODE
  targets:
  - select:
      kind: RayCluster
    fieldPaths:
    - spec.workerGroupSpecs.0.rayStartParams.num-gpus

# Replace GPU resources in worker pods
- source:
    kind: ConfigMap
    name: cluster-config
    fieldPath: data.NUM_GPU_PER_NODE
  targets:
  - select:
      kind: RayCluster
    fieldPaths:
    - spec.workerGroupSpecs.0.template.spec.containers.0.resources.limits.nvidia\\.com/gpu
    - spec.workerGroupSpecs.0.template.spec.containers.0.resources.requests.nvidia\\.com/gpu

# Replace EFA resources in worker pods
- source:
    kind: ConfigMap
    name: cluster-config
    fieldPath: data.NUM_EFA_PER_NODE
  targets:
  - select:
      kind: RayCluster
    fieldPaths:
    - spec.workerGroupSpecs.0.template.spec.containers.0.resources.limits.vpc\\.amazonaws\\.com/efa
    - spec.workerGroupSpecs.0.template.spec.containers.0.resources.requests.vpc\\.amazonaws\\.com/efa
EOF

echo "Generated ${KUSTOMIZATION_FILE} successfully"
echo "You can now deploy using: kubectl apply -k ${SCRIPT_DIR}/"
