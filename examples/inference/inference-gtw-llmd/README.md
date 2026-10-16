
# SageMaker HyperPod Inference Gateway with llm-d

Deploy a multi-model LLM inference stack using **llm-d** and the **SageMaker HyperPod Inference Gateway** on Amazon EKS. Inference requests flow from a single gateway endpoint to model servers via GPU-aware, body-based routing.

> **Tested on:** macOS (Apple Silicon), CDK 2.1144+, Python 3.14, EKS 1.31, us-west-2
> **Time to deploy:** ~60–90 minutes (excluding quota requests)
> **Model:** Qwen/Qwen2.5-7B-Instruct (ungated, no HuggingFace token required)
> **GPU:** ml.g5.2xlarge (1x A10G, 24GB VRAM)

---

## Prerequisites

| Requirement | Minimum Version |
|---|---|
| AWS CLI | v2 |
| Node.js | 20+ |
| Python | 3.11+ |
| CDK CLI | **2.1144.0+** (`npm install -g aws-cdk@latest`) |
| kubectl | 1.28+ |
| helm | 3.14+ |
| jq | any |

> **⚠️ Quota check — do this first:**
> ```bash
> aws service-quotas list-service-quotas \
>   --service-code sagemaker \
>   --region us-west-2 \
>   --query 'Quotas[?contains(QuotaName, `HyperPod`)].{Name:QuotaName,Value:Value}' \
>   --output table
> ```
> You need at least **1x `ml.g5.2xlarge`** for HyperPod cluster usage. The `ml.g5.2xlarge` does **not** support deep health checks — the create script has these disabled.
>
> **Note on instance size:** `ml.g5.8xlarge` and larger support deep health checks. If you use `ml.g5.2xlarge`, do NOT include `OnStartDeepHealthChecks` in the cluster config.

---

## Project Structure

```
.
├── README.md
├── requirements.txt
├── cdk.json
├── .gitignore
├── .gitlab-ci.yml
├── cdk/
│   └── app.py                          # CDK stack: VPC, EKS, FSx, IAM, S3
├── scripts/
│   ├── create_hyperpod_cluster.sh      # Creates HyperPod cluster on EKS
│   └── test_inference_gateway.sh       # Validates gateway routing
└── k8s/
    ├── 01-qwen2.5-7b.yaml             # InferenceEndpointConfig: Qwen2.5 7B
    └── 03-gateway-routes.yaml          # Gateway + HTTPRoutes
```

---

## Step 1: Deploy Infrastructure with CDK

**1a. Create a virtual environment and install dependencies:**

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

> **Why the venv?** macOS with Homebrew-managed Python blocks system-wide pip installs (PEP 668). Always use a virtual environment.

**1b. Set your AWS account ID and replace the placeholder:**

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

python3 << 'SCRIPT'
import os
path = "cdk/app.py"
acct = os.environ["ACCOUNT_ID"]
with open(path, "r") as f:
    content = f.read()
content = content.replace("REPLACE_WITH_YOUR_ACCOUNT_ID", acct)
with open(path, "w") as f:
    f.write(content)
print(f"Replaced with account ID: {acct}")
SCRIPT
```

> **Tip:** Don't commit your account ID. Revert after deploying: `git checkout cdk/app.py`

**1c. Bootstrap and deploy:**

```bash
cdk bootstrap aws://${ACCOUNT_ID}/us-west-2
cdk deploy --outputs-file cdk-outputs.json
```

Save the outputs — they're used in every subsequent step.

---

## Step 2: Configure EKS Access

**2a. Switch authentication mode** (HyperPod requires `API_AND_CONFIG_MAP`):

```bash
aws eks update-cluster-config \
  --name hyperpod-ig-demo \
  --region us-west-2 \
  --access-config authenticationMode=API_AND_CONFIG_MAP
```

Wait ~30 seconds for the update.

**2b. Grant your IAM role cluster admin access:**

```bash
CALLER_ROLE=$(aws sts get-caller-identity --query 'Arn' --output text | sed 's|assumed-role/\(.*\)/.*|role/\1|; s|sts|iam|')

aws eks create-access-entry \
  --cluster-name hyperpod-ig-demo \
  --principal-arn ${CALLER_ROLE} \
  --region us-west-2

aws eks associate-access-policy \
  --cluster-name hyperpod-ig-demo \
  --principal-arn ${CALLER_ROLE} \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster \
  --region us-west-2
```

**2c. Configure kubectl:**

```bash
aws eks update-kubeconfig --name hyperpod-ig-demo --region us-west-2
kubectl get nodes
```

Expected: `No resources found` — correct, no nodes yet.

---

## Step 3: Install HyperPod EKS Dependencies

```bash
# Add Helm repos
helm repo add jetstack https://charts.jetstack.io
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Clone and build the HyperPod Helm chart
git clone https://github.com/aws/sagemaker-hyperpod-cli.git /tmp/hyperpod-cli
helm dependency build /tmp/hyperpod-cli/helm_chart/HyperPodHelmChart

# Install
helm install hyperpod-dependencies \
  /tmp/hyperpod-cli/helm_chart/HyperPodHelmChart \
  --namespace kube-system \
  --create-namespace
```

---

## Step 4: Create the HyperPod Cluster

**4a. Upload the lifecycle script:**

```bash
BUCKET=$(python3 -c "import json; print(json.load(open('cdk-outputs.json'))['HyperPodInferenceGatewayStack']['LifecycleBucketName'])")

cat > /tmp/on_create.sh << 'EOF'
#!/bin/bash
set -ex
echo "==> HyperPod lifecycle script starting..."
echo "==> Node setup complete."
EOF

aws s3 cp /tmp/on_create.sh s3://${BUCKET}/lifecycle-scripts/
```

**4b. Create the cluster:**

```bash
ROLE_ARN=$(python3 -c "import json; print(json.load(open('cdk-outputs.json'))['HyperPodInferenceGatewayStack']['HyperPodRoleArn'])")
SUBNET_ID=$(python3 -c "import json; print(json.load(open('cdk-outputs.json'))['HyperPodInferenceGatewayStack']['PrivateSubnetId'])")
SG_ID=$(python3 -c "import json; print(json.load(open('cdk-outputs.json'))['HyperPodInferenceGatewayStack']['SecurityGroupId'])")

./scripts/create_hyperpod_cluster.sh "${ROLE_ARN}" "${SUBNET_ID}" "${SG_ID}"
```

**4c. Monitor** (~10–15 minutes):

```bash
while true; do
  STATUS=$(aws sagemaker describe-cluster --cluster-name hyperpod-ig-demo --region us-west-2 --query 'ClusterStatus' --output text)
  echo "$(date): $STATUS"
  if [ "$STATUS" = "InService" ] || [ "$STATUS" = "Failed" ]; then break; fi
  sleep 30
done
```

---

## Step 5: Fix Security Groups (Critical)

**This is the most important step.** The CDK-created EKS cluster security group and the HyperPod security group are different. Without cross-SG rules, HyperPod nodes cannot communicate with the EKS control plane and will never join the cluster.

**5a. Get the EKS cluster security group:**

```bash
EKS_SG=$(aws eks describe-cluster --name hyperpod-ig-demo --region us-west-2 \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
echo "EKS Cluster SG: ${EKS_SG}"
```

**5b. Allow bidirectional traffic between EKS and HyperPod SGs:**

```bash
# EKS SG → allow inbound from HyperPod SG
aws ec2 authorize-security-group-ingress \
  --group-id ${EKS_SG} \
  --protocol -1 \
  --source-group ${SG_ID} \
  --region us-west-2

# HyperPod SG → allow inbound from EKS SG
aws ec2 authorize-security-group-ingress \
  --group-id ${SG_ID} \
  --protocol -1 \
  --source-group ${EKS_SG} \
  --region us-west-2
```

> **If you get "already exists" errors, that's fine — the rules are already in place.**

**5c. Verify HyperPod nodes join the EKS cluster:**

```bash
kubectl get nodes --watch
```

You should see nodes with `hyperpod-` prefix joining. Wait until you see both the controller (`ml.m5.2xlarge`) and GPU worker (`ml.g5.2xlarge`).

---

## Step 6: Add EKS System Node Group

The Inference Operator, Gateway, KEDA, and ALB pods need regular compute nodes. Create a managed node group with a **separate IAM role** (the HyperPod execution role doesn't have the `ec2.amazonaws.com` trust principal).

**6a. Create the EKS node role:**

```bash
aws iam create-role \
  --role-name HyperPodEksNodeRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam attach-role-policy --role-name HyperPodEksNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-role-policy --role-name HyperPodEksNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam attach-role-policy --role-name HyperPodEksNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

**6b. Create the managed node group:**

```bash
aws eks create-nodegroup \
  --cluster-name hyperpod-ig-demo \
  --nodegroup-name system-nodes \
  --node-role arn:aws:iam::${ACCOUNT_ID}:role/HyperPodEksNodeRole \
  --subnets ${SUBNET_ID} \
  --instance-types m5.xlarge \
  --scaling-config minSize=2,maxSize=3,desiredSize=3 \
  --region us-west-2
```

> **Why 3 nodes?** The `ml.g5.2xlarge` HyperPod node has a low max-pods limit. System pods (ALB, KEDA, CoreDNS, CSI drivers) can fill it up, leaving no room for the model pod. Three system nodes ensure enough capacity.

**6c. Taint the GPU node** to prevent non-GPU workloads from scheduling on it:

```bash
GPU_NODE=$(kubectl get nodes -l node.kubernetes.io/instance-type=ml.g5.2xlarge -o jsonpath='{.items[0].metadata.name}')
kubectl taint nodes ${GPU_NODE} nvidia.com/gpu=true:NoSchedule
```

---

## Step 7: Install CSI Drivers and Webhook Certificate

**7a. Install CSI drivers:**

```bash
aws eks create-addon \
  --cluster-name hyperpod-ig-demo \
  --addon-name aws-mountpoint-s3-csi-driver \
  --region us-west-2

aws eks create-addon \
  --cluster-name hyperpod-ig-demo \
  --addon-name aws-fsx-csi-driver \
  --region us-west-2
```

**7b. Create the self-signed ClusterIssuer and webhook certificate:**

```bash
kubectl create namespace hyperpod-inference-system 2>/dev/null || true

cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: webhook-server-cert
  namespace: hyperpod-inference-system
spec:
  secretName: webhook-server-cert
  duration: 8760h
  renewBefore: 720h
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
    - hyperpod-inference-controller-manager-service.hyperpod-inference-system.svc
    - hyperpod-inference-controller-manager-service.hyperpod-inference-system.svc.cluster.local
  privateKey:
    algorithm: RSA
    size: 2048
EOF
```

Verify:

```bash
kubectl get certificate -n hyperpod-inference-system
# Should show READY=True
```

---

## Step 8: Install the Inference Operator (SageMaker Console)

1. Go to **SageMaker AI Console** → **HyperPod Clusters** → **Cluster Management**
2. Select **hyperpod-ig-demo**
3. Navigate to the **Inference** tab
4. Select **Quick Install**

**8a. Verify pods are running:**

```bash
kubectl get pods -n hyperpod-inference-system
```

**8b. Set the HyperPod cluster ARN** (the controller can't auto-detect it):

```bash
CLUSTER_ARN=$(aws sagemaker describe-cluster --cluster-name hyperpod-ig-demo --region us-west-2 --query 'ClusterArn' --output text)

kubectl set env deployment/hyperpod-inference-controller-manager \
  -n hyperpod-inference-system \
  HYPERPOD_CLUSTER_ARN=${CLUSTER_ARN}
```

**8c. Wait for the controller to be ready:**

```bash
kubectl get pods -n hyperpod-inference-system -l control-plane=hyperpod-inference-controller-manager --watch
```

Wait until it shows `1/1 Running`.

---

## Step 9: Deploy the Model

```bash
kubectl apply -f k8s/01-qwen2.5-7b.yaml
```

Monitor the pod (model download takes 5–10 minutes):

```bash
kubectl get pods -n default --watch
```

Wait until it shows `3/3 Running`.

> **If the pod is stuck in `Pending`:** Check `kubectl describe pod <pod-name> -n default | tail -10`. Common causes:
> - `Too many pods` — taint the GPU node and evict non-GPU pods (see Step 6c)
> - `node(s) didn't match Pod's node affinity/selector` — GPU node hasn't joined yet (check Step 5)

---

## Step 10: Test the Inference Endpoint

**10a. Port-forward to the model pod:**

```bash
POD_NAME=$(kubectl get pods -n default -l model=qwen2-5-7b -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward pod/${POD_NAME} 8080:8000 -n default &
```

**10b. Send a test request:**

```bash
curl -s -X POST "http://localhost:8080/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwen/Qwen2.5-7B-Instruct",
    "messages": [
      {"role": "user", "content": "Explain what an inference gateway does in two sentences."}
    ],
    "max_tokens": 100
  }' | python3 -m json.tool
```

Expected response:

```json
{
    "id": "chatcmpl-...",
    "model": "Qwen/Qwen2.5-7B-Instruct",
    "choices": [
        {
            "message": {
                "role": "assistant",
                "content": "An inference gateway acts as an intermediary for routing and managing machine learning model predictions..."
            },
            "finish_reason": "stop"
        }
    ]
}
```

**10c. Run the full test suite:**

```bash
chmod +x scripts/test_inference_gateway.sh
./scripts/test_inference_gateway.sh "http://localhost:8080"
```

**10d. Stop port-forward:**

```bash
kill %1
```

---

## Cleanup

Run in this order to avoid orphaned resources:

```bash
# 1. Remove model deployments and gateway
kubectl delete -f k8s/03-gateway-routes.yaml 2>/dev/null
kubectl delete -f k8s/01-qwen2.5-7b.yaml

# 2. Delete the HyperPod cluster
aws sagemaker delete-cluster --cluster-name hyperpod-ig-demo --region us-west-2

# 3. Remove the EKS system node group
aws eks delete-nodegroup \
  --cluster-name hyperpod-ig-demo \
  --nodegroup-name system-nodes \
  --region us-west-2

# 4. Uninstall Helm dependencies
helm uninstall hyperpod-dependencies --namespace kube-system

# 5. Remove the EKS node role
aws iam detach-role-policy --role-name HyperPodEksNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam detach-role-policy --role-name HyperPodEksNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam detach-role-policy --role-name HyperPodEksNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam delete-role --role-name HyperPodEksNodeRole

# 6. Destroy CDK stack
cdk destroy
```

---

## Troubleshooting

### HyperPod cluster creation fails

| Error | Fix |
|---|---|
| `missing one or more required dependencies` | Install HyperPod Helm chart (Step 3) |
| `CONFIG_MAP authentication mode are not supported` | Switch to `API_AND_CONFIG_MAP` (Step 2a) |
| `VpcConfig is required` | Add `--vpc-config` to create script |
| `ResourceLimitExceeded` for `ml.g5.2xlarge` | Request quota increase |
| `deep health check...unsupported instance type` | Remove `OnStartDeepHealthChecks` from create script |

### HyperPod nodes not joining EKS cluster

**This is the #1 issue.** The CDK-created EKS cluster SG and HyperPod SG are different. Without cross-SG ingress rules, nodes can't reach the EKS API.

```bash
# Verify SGs are different
EKS_SG=$(aws eks describe-cluster --name hyperpod-ig-demo --region us-west-2 \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
echo "EKS SG: ${EKS_SG}"
echo "HyperPod SG: ${SG_ID}"
# If different → apply Step 5
```

### Inference controller stuck in Init:0/1

| Event Message | Fix |
|---|---|
| `secret "webhook-server-cert" not found` | Create the certificate (Step 7b) |
| `S3 CSI driver not installed` | Install S3 CSI add-on (Step 7a) |
| `FSx CSI driver not installed` | Install FSx CSI add-on (Step 7a) |

### Inference controller CrashLoopBackOff

| Error in logs | Fix |
|---|---|
| `cluster name label not found` | Set `HYPERPOD_CLUSTER_ARN` env var (Step 8b) |
| `Specified cluster not found` | Cluster was recreated — update the ARN (Step 8b) |

### Model pod stuck in Pending

| Event Message | Fix |
|---|---|
| `Too many pods` | Taint GPU node + evict non-GPU pods (Step 6c) |
| `node(s) didn't match Pod's node affinity/selector` | GPU node hasn't joined — check Step 5 |
| `Insufficient nvidia.com/gpu` | GPU node not provisioned — check `aws sagemaker list-cluster-nodes` |

### Gated model error (401 Unauthorized)

If using a gated model like Llama 3.1, you need a HuggingFace token. Switch to an ungated model like `Qwen/Qwen2.5-7B-Instruct` instead.

### kubectl authentication errors

Isengard sessions expire frequently. Re-authenticate:

```bash
aws sts get-caller-identity
aws eks update-kubeconfig --name hyperpod-ig-demo --region us-west-2
```

### System nodes disappear (DesiredSize: 0)

Isengard cost controls may scale down the ASG over weekends:

```bash
aws eks update-nodegroup-config \
  --cluster-name hyperpod-ig-demo \
  --nodegroup-name system-nodes \
  --scaling-config minSize=2,maxSize=3,desiredSize=3 \
  --region us-west-2
```

---

## Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │              Inference Gateway               │
                    │                                             │
  Client Request    │  ┌─────────────┐    ┌──────────────────┐   │
  POST /v1/chat ───►│  │ Body-Based  │───►│   HTTPRoute      │   │
  model: qwen       │  │   Router    │    │   (per model)    │   │
                    │  │  (reads     │    │                  │   │
                    │  │   model     │    │  qwen-route ─────┼──►│ Qwen2.5 7B (vLLM)
                    │  │   field)    │    │                  │   │
                    │  └─────────────┘    └──────────────────┘   │
                    │                                             │
                    └─────────────────────────────────────────────┘
                                          │
                              HyperPod EKS Cluster
                              (ml.g5.2xlarge GPU node)
```

---

## Key Lessons Learned

1. **Security groups are the #1 blocker** — CDK creates a separate EKS cluster SG. HyperPod nodes use a different SG. Without cross-SG rules, nodes never join.
2. **`ml.g5.2xlarge` doesn't support deep health checks** — only `g5.8xlarge+` does. Remove `OnStartDeepHealthChecks` from the cluster config.
3. **EKS auth mode must be `API_AND_CONFIG_MAP`** — HyperPod doesn't support `CONFIG_MAP` only.
4. **The Inference Operator needs `HYPERPOD_CLUSTER_ARN`** — it can't auto-detect from node labels on the controller node.
5. **Taint the GPU node** — system pods will fill up the low max-pods limit on `ml.g5.2xlarge`, leaving no room for the model pod.
6. **Use ungated models** — Llama 3.1 requires a HuggingFace token. Qwen2.5-7B-Instruct is fully open and works out of the box.
7. **System nodes may disappear** — Isengard cost controls can scale the ASG to 0 over weekends. Always check `kubectl get nodes` first.
8. **Webhook certificate must be created manually** — cert-manager is installed by Quick Install but doesn't auto-create the webhook cert.

---

## References

- [Introducing Amazon SageMaker HyperPod Inference Gateway](https://aws.amazon.com/blogs/machine-learning/introducing-amazon-sagemaker-hyperpod-inference-gateway/)
- [Inference Gateway Documentation](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-model-deployment-inference-gateway.html)
- [Setting up HyperPod for Model Deployment](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-model-deployment-setup.html)
- [Installing EKS Dependencies](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-eks-install-packages-using-helm-chart.html)
- [Inference Operator Troubleshooting](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-model-deployment-ts.html)
- [HyperPod CLI Helm Chart](https://github.com/aws/sagemaker-hyperpod-cli/tree/main/helm_chart)
- [Envoy AI Gateway with llm-d](https://llm-d.ai/docs/infrastructure/gateway/envoy-ai-gateway)
- [Gateway API Inference Extension (GEP-3567)](https://gateway-api.sigs.k8s.io/geps/gep-3567/)
- [Deploy Models on HyperPod](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-model-deployment-deploy-ftm.html)
