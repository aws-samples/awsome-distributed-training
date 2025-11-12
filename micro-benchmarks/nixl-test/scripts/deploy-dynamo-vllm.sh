#!/usr/bin/env bash
# deploy-dynamo-vllm.sh - Deploy vLLM with NVIDIA Dynamo
set -euo pipefail

# Load environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ ! -f "${PROJECT_ROOT}/examples/deployment-env.sh" ]; then
    echo "❌ Error: deployment-env.sh not found. Run from project root or set environment variables manually."
    exit 1
fi

source "${PROJECT_ROOT}/examples/deployment-env.sh"

# Verify required environment variables
required_vars=(
    "NAMESPACE"
    "DEPLOYMENT_NAME"
    "MODEL_ID"
    "TENSOR_PARALLEL_SIZE"
    "MAX_MODEL_LEN"
    "GPU_MEMORY_UTILIZATION"
    "KV_CACHE_DTYPE"
    "MAX_NUM_SEQS"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "❌ Error: Required environment variable $var is not set"
        exit 1
    fi
done

echo "🚀 Deploying vLLM with NVIDIA Dynamo"
echo "=================================="
echo "Namespace: $NAMESPACE"
echo "Deployment: $DEPLOYMENT_NAME"
echo "Model: $MODEL_ID"
echo "Tensor Parallel: $TENSOR_PARALLEL_SIZE"
echo "Max Model Length: $MAX_MODEL_LEN"
echo "=================================="

# Generate deployment YAML
YAML_FILE="${DEPLOYMENT_NAME}.yaml"

cat > "${YAML_FILE}" << EOF
apiVersion: nvidia.com/v1alpha1
kind: DynamoGraphDeployment
metadata:
  name: ${DEPLOYMENT_NAME}
  namespace: ${NAMESPACE}
spec:
  services:
    ${FRONTEND_NAME}:
      dynamoNamespace: ${DEPLOYMENT_NAME}
      componentType: main
      replicas: 1
      resources:
        requests:
          cpu: "1"
          memory: "2Gi"
        limits:
          cpu: "1"
          memory: "2Gi"
      livenessProbe:
        httpGet:
          path: /health
          port: 8000
        initialDelaySeconds: 900
        periodSeconds: 120
        timeoutSeconds: 60
        failureThreshold: 15
      readinessProbe:
        exec:
          command:
            - /bin/sh
            - -c
            - 'curl -s http://localhost:8000/health | jq -e ".status == \\"healthy\\""'
        initialDelaySeconds: 900
        periodSeconds: 120
        timeoutSeconds: 60
        failureThreshold: 15
      extraPodSpec:
        terminationGracePeriodSeconds: 300
        mainContainer:
          image: nvcr.io/nvidia/ai-dynamo/vllm-runtime:${RELEASE_VERSION}
          workingDir: /workspace/components/backends/vllm
          command:
            - /bin/sh
            - -c
          args:
            - "python3 -m dynamo.frontend --http-port 8000"
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 60"]
    ${WORKER_NAME}:
      envFromSecret: hf-token-secret
      dynamoNamespace: ${DEPLOYMENT_NAME}
      componentType: worker
      replicas: 1
      resources:
        requests:
          cpu: "32"
          memory: "1800Gi"
          gpu: "${TENSOR_PARALLEL_SIZE}"
        limits:
          cpu: "32"
          memory: "1800Gi"
          gpu: "${TENSOR_PARALLEL_SIZE}"
      envs:
        - { name: DYN_SYSTEM_ENABLED, value: "true" }
        - { name: DYN_SYSTEM_USE_ENDPOINT_HEALTH_STATUS, value: "[\\"generate\\"]" }
        - { name: DYN_SYSTEM_PORT, value: "9090" }
        - { name: DYN_LOG, value: "DEBUG" }
        - { name: NCCL_DEBUG, value: "WARN" }
        - { name: NCCL_SOCKET_IFNAME, value: "eth0" }
        - { name: CUDA_VISIBLE_DEVICES, value: "0,1,2,3,4,5,6,7" }
        - { name: MODEL_ID, value: "${MODEL_ID}" }
        - { name: MODEL_DIR, value: "${MODEL_DIR}" }
        - { name: CACHE_DIR, value: "${CACHE_DIR}" }
        - { name: TENSOR_PARALLEL_SIZE, value: "${TENSOR_PARALLEL_SIZE}" }
        - { name: MAX_MODEL_LEN, value: "${MAX_MODEL_LEN}" }
        - { name: GPU_MEMORY_UTILIZATION, value: "${GPU_MEMORY_UTILIZATION}" }
        - { name: KV_CACHE_DTYPE, value: "${KV_CACHE_DTYPE}" }
        - { name: BLOCK_SIZE, value: "${BLOCK_SIZE}" }
        - { name: MAX_NUM_SEQS, value: "${MAX_NUM_SEQS}" }
        - { name: METRICS_PORT, value: "${METRICS_PORT}" }
        - name: HUGGING_FACE_HUB_TOKEN
          valueFrom: { secretKeyRef: { name: hf-token-secret, key: HF_TOKEN } }
        - name: HF_TOKEN
          valueFrom: { secretKeyRef: { name: hf-token-secret, key: HF_TOKEN } }
      livenessProbe:
        httpGet:
          path: /health
          port: 9090
        initialDelaySeconds: 1800
        periodSeconds: 120
        timeoutSeconds: 60
        failureThreshold: 10
      readinessProbe:
        httpGet:
          path: /health
          port: 9090
        initialDelaySeconds: 1800
        periodSeconds: 120
        timeoutSeconds: 60
        failureThreshold: 15
      extraPodSpec:
        terminationGracePeriodSeconds: 900
        tolerations:
        - key: "nvidia.com/gpu"
          operator: "Exists"
          effect: "NoSchedule"
        nodeSelector:
          ${NODE_SELECTOR}
        mainContainer:
          startupProbe:
            httpGet:
              path: /health
              port: 9090
            periodSeconds: 60
            timeoutSeconds: 60
            failureThreshold: 60
          image: nvcr.io/nvidia/ai-dynamo/vllm-runtime:${RELEASE_VERSION}
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 180"]
          command: ["/bin/bash", "-c"]
          args:
            - |
              echo "Pre-downloading model to local directory..." &&
              python3 -c "
              import os
              from huggingface_hub import snapshot_download
              token = os.environ.get('HF_TOKEN')
              model = os.environ.get('MODEL_ID')
              local_dir = os.environ.get('MODEL_DIR')
              snapshot_download(
                  repo_id=model,
                  local_dir=local_dir,
                  token=token
              )
              " &&
              echo "Starting vLLM worker with pre-downloaded model..." &&
              python3 -m dynamo.vllm \\
                --model \${MODEL_DIR} \\
                --served-model-name \${MODEL_ID} \\
                --tensor-parallel-size \${TENSOR_PARALLEL_SIZE} \\
                --max-model-len \${MAX_MODEL_LEN} \\
                --gpu-memory-utilization \${GPU_MEMORY_UTILIZATION} \\
                --max-num-seqs \${MAX_NUM_SEQS_DECODE} \\
                --trust-remote-code \\
                --download-dir \${CACHE_DIR} \\
                --kv-cache-dtype \${KV_CACHE_DTYPE} \\
                --disable-log-requests \\
                --max-num-seqs \${MAX_NUM_SEQS} \\
                --tokenizer \${MODEL_DIR} \\
                2>&1 | tee vllm_worker_\${HOSTNAME}.log
EOF

echo "✅ Generated deployment YAML: ${YAML_FILE}"

# Apply deployment
echo "📦 Applying deployment to Kubernetes..."
kubectl apply -f "${YAML_FILE}"

echo "⏳ Waiting for pods to be created..."
sleep 10

# Get pod names
export FRONTEND_POD=$(kubectl get pods -n $NAMESPACE 2>/dev/null | grep "^${DEPLOYMENT_NAME}-frontend-" | head -1 | awk '{print $1}')
export WORKER_POD=$(kubectl get pods -n $NAMESPACE 2>/dev/null | grep "^${DEPLOYMENT_NAME}-vllmworker-" | head -1 | awk '{print $1}')

echo ""
echo "🔍 Deployment Details:"
echo "   Namespace: $NAMESPACE"
echo "   Deployment: $DEPLOYMENT_NAME"
echo "   Frontend Pod: $FRONTEND_POD"
echo "   Worker Pod: $WORKER_POD"
echo "   Frontend Service: $FRONTEND_SVC"
echo ""
echo "📊 Monitor deployment:"
echo "   kubectl get pods -n $NAMESPACE -l dynamoNamespace=$DEPLOYMENT_NAME -w"
echo ""
echo "📜 View logs:"
echo "   kubectl logs -f $FRONTEND_POD -n $NAMESPACE"
echo "   kubectl logs -f $WORKER_POD -n $NAMESPACE"
echo ""
echo "🔌 Port forward (run in separate terminal):"
echo "   kubectl port-forward svc/$FRONTEND_SVC 8080:8080 -n $NAMESPACE"
echo ""
echo "✅ Deployment initiated. Wait for pods to be ready (~15-30 minutes for model download)"
