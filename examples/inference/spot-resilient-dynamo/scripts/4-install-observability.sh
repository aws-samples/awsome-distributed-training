#!/bin/bash
# 4-install-observability.sh — Install Prometheus + Grafana
set -euo pipefail

echo "=== Installing kube-prometheus-stack ==="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update prometheus-community

helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --wait --timeout 300s

echo ""
echo "=== Verify ==="
kubectl get pods -n monitoring | head -10

echo ""
echo "=== Access Grafana ==="
echo "Password: kubectl get secret -n monitoring kube-prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo"
echo "Port-forward: kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80"
echo "Open: http://localhost:3000"
