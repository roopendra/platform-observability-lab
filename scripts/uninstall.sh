#!/usr/bin/env bash
set -euo pipefail

echo "Removing VictoriaLogs Helm release..."
helm uninstall victoria-logs -n logging 2>/dev/null || true

echo "Removing OpenTelemetry Helm release..."
helm uninstall opentelemetry-collector -n opentelemetry 2>/dev/null || true

echo "Removing monitoring Helm releases..."
helm uninstall elasticsearch-exporter -n monitoring 2>/dev/null || true
helm uninstall grafana -n monitoring 2>/dev/null || true
helm uninstall prometheus -n monitoring 2>/dev/null || true

echo "Removing OpenTelemetry, Jaeger, demo, and logging namespaces..."
kubectl delete namespace opentelemetry --ignore-not-found=true
kubectl delete namespace logging --ignore-not-found=true

echo "Removing monitoring and Elasticsearch namespaces..."
kubectl delete namespace monitoring --ignore-not-found=true
kubectl delete namespace elastic --ignore-not-found=true

echo
echo "Done. Minikube itself was not deleted."
echo "Run ./scripts/start.sh to recreate the complete lab."
