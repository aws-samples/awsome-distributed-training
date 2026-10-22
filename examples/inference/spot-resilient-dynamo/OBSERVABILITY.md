# Observability — Spot-Resilient NVIDIA Dynamo

## Stack

| Component | Purpose |
|---|---|
| Prometheus | Scrapes Dynamo Frontend `/metrics` and kubelet metrics |
| Grafana | Dashboards for in-flight request count, pod lifecycle, node status |
| kube-prometheus-stack | Helm chart that installs both + node-exporter + kube-state-metrics |

## Install

```bash
./scripts/05-install-observability.sh
```

This runs:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

## Access Grafana

```bash
# Get admin password
kubectl get secret -n monitoring kube-prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d; echo

# Port-forward
kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80
# Open http://localhost:3000
```

## Key Metrics to Watch During the Interruption Test

### Dynamo Frontend (port 8000 /metrics)

- **Request count**: total requests received by the Frontend
- **HTTP status codes**: 200 (success) vs 503 (no healthy worker)

### Kubernetes

- **Pod status transitions**: Running → Terminating → Pending → Running
  (visible in kube-state-metrics `kube_pod_status_phase`)
- **Node status**: Ready → NotReady → new node Ready
  (`kube_node_status_condition`)

### NTH

- **Events**: `kubectl get events --field-selector reason=SpotInterruption -A`
- **NTH logs**: `kubectl logs -n kube-system -l app.kubernetes.io/name=aws-node-termination-handler`

## Recommended Grafana Dashboards

1. **Kubernetes / Pods** (built-in) — watch pod phase transitions during drain
2. **Node Exporter** (built-in) — confirm node termination + replacement
3. **Custom: Dynamo Frontend** — create a panel querying the Frontend's `/metrics`
   endpoint for request success/failure rate

## During the FIS Test

Open three terminal panes:
```bash
# Pane 1: watch pods
kubectl get pods -n dynamo -w

# Pane 2: watch nodes
kubectl get nodes -w

# Pane 3: watch NTH events
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-node-termination-handler -f
```
