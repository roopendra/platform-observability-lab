#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-lab-cluster}"
PROMETHEUS_CHART_VERSION="${PROMETHEUS_CHART_VERSION:-29.27.0}"
GRAFANA_CHART_VERSION="${GRAFANA_CHART_VERSION:-10.5.15}"
EXPORTER_CHART_VERSION="${EXPORTER_CHART_VERSION:-7.4.0}"
OTEL_COLLECTOR_CHART_VERSION="${OTEL_COLLECTOR_CHART_VERSION:-0.172.1}"
VICTORIALOGS_CHART_VERSION="${VICTORIALOGS_CHART_VERSION:-0.13.9}"

OTEL_DEMO_IMAGE="${OTEL_DEMO_IMAGE:-otel-demo:1.3}"
OTEL_USER_IMAGE="${OTEL_USER_IMAGE:-otel-user-service:1.0}"
OTEL_INVENTORY_IMAGE="${OTEL_INVENTORY_IMAGE:-otel-inventory-service:1.0}"

log() { printf '\n==> %s\n' "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' is required but was not found in PATH." >&2
    exit 1
  }
}

for cmd in docker kubectl k3d helm; do
  require_cmd "$cmd"
done

log "Checking the Docker-compatible container runtime"
if ! docker info >/dev/null 2>&1; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    open -a OrbStack || true
    echo "Waiting for OrbStack..."
    for _ in {1..60}; do
      if docker info >/dev/null 2>&1; then break; fi
      sleep 2
    done
  fi
fi

docker info >/dev/null 2>&1 || {
  echo "ERROR: Docker is unavailable. Start OrbStack on macOS (or your Docker-compatible runtime) and rerun." >&2
  exit 1
}

log "Checking k3d cluster and Kubernetes context"
if ! k3d cluster list -o json | grep -Eq '"name"[[:space:]]*:[[:space:]]*"'"$K3D_CLUSTER_NAME"'"'; then
  echo "ERROR: k3d cluster '$K3D_CLUSTER_NAME' was not found. Create it first with: k3d cluster create '$K3D_CLUSTER_NAME'" >&2
  exit 1
fi
kubectl config use-context "k3d-$K3D_CLUSTER_NAME" >/dev/null
kubectl get nodes

log "Creating namespaces"
kubectl apply -f namespaces.yaml

log "Deploying Elasticsearch"
kubectl apply -f elasticsearch/
kubectl rollout status statefulset/es-master -n elastic --timeout=180s
kubectl rollout status statefulset/es-data -n elastic --timeout=180s

log "Adding Helm repositories"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo add vm https://victoriametrics.github.io/helm-charts/ >/dev/null 2>&1 || true
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo update

log "Installing/upgrading NGINX Ingress Controller"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443
kubectl rollout status deployment/ingress-nginx-controller \
  -n ingress-nginx --timeout=180s

log "Installing/upgrading Prometheus"
helm upgrade --install prometheus \
  prometheus-community/prometheus \
  --namespace monitoring \
  --create-namespace \
  --version "$PROMETHEUS_CHART_VERSION" \
  -f monitoring/prometheus.yaml

log "Installing/upgrading Grafana"
helm upgrade --install grafana \
  grafana/grafana \
  --namespace monitoring \
  --version "$GRAFANA_CHART_VERSION" \
  -f monitoring/grafana.yaml

log "Installing/upgrading Elasticsearch exporter"
helm upgrade --install elasticsearch-exporter \
  prometheus-community/prometheus-elasticsearch-exporter \
  --namespace monitoring \
  --version "$EXPORTER_CHART_VERSION" \
  -f monitoring/elasticsearch-exporter-values.yaml

log "Installing/upgrading VictoriaLogs"
helm upgrade --install victoria-logs \
  vm/victoria-logs-single \
  --namespace logging \
  --create-namespace \
  --version "$VICTORIALOGS_CHART_VERSION" \
  -f logging/victoria-logs-values.yaml

log "Installing/upgrading OpenTelemetry Collector"
helm upgrade --install opentelemetry-collector \
  open-telemetry/opentelemetry-collector \
  --namespace opentelemetry \
  --version "$OTEL_COLLECTOR_CHART_VERSION" \
  -f opentelemetry/collector-values.yaml

log "Deploying Jaeger"
kubectl apply -f tracing/jaeger.yaml

log "Building and importing distributed OTel demo images into k3d"
[[ -d otel-demo ]] || { echo "ERROR: otel-demo/ directory not found." >&2; exit 1; }
[[ -d otel-demo/user-service ]] || { echo "ERROR: otel-demo/user-service/ directory not found." >&2; exit 1; }
[[ -d otel-demo/inventory-service ]] || { echo "ERROR: otel-demo/inventory-service/ directory not found." >&2; exit 1; }

docker build -t "$OTEL_DEMO_IMAGE" otel-demo/
docker build -t "$OTEL_USER_IMAGE" otel-demo/user-service/
docker build -t "$OTEL_INVENTORY_IMAGE" otel-demo/inventory-service/
k3d image import -c "$K3D_CLUSTER_NAME" "$OTEL_DEMO_IMAGE" "$OTEL_USER_IMAGE" "$OTEL_INVENTORY_IMAGE"

log "Deploying distributed demo application"
kubectl apply -f otel-demo/user-service/deployment.yaml
kubectl apply -f otel-demo/inventory-service/deployment.yaml
kubectl apply -f otel-demo/deployment.yaml
kubectl apply -f otel-demo/ingress.yaml

log "Applying Ingress resources"
kubectl apply -f elasticsearch/es-ingress.yaml
kubectl apply -f monitoring/monitoring-ingress.yaml
kubectl apply -f tracing/jaeger-ingress.yaml

log "Waiting for workloads"
kubectl rollout status deployment/prometheus-server -n monitoring --timeout=180s
kubectl rollout status deployment/grafana -n monitoring --timeout=180s

EXPORTER_POD="$(kubectl get pods -n monitoring \
  -l app.kubernetes.io/instance=elasticsearch-exporter \
  -o jsonpath='{.items[0].metadata.name}')"
kubectl wait --for=condition=Ready "pod/$EXPORTER_POD" \
  -n monitoring --timeout=180s

kubectl wait --for=condition=Ready \
  -l app.kubernetes.io/instance=victoria-logs \
  -n logging pod --timeout=180s

kubectl rollout status deployment/opentelemetry-collector \
  -n opentelemetry --timeout=180s
kubectl rollout status deployment/jaeger \
  -n opentelemetry --timeout=180s
kubectl rollout status deployment/user-service \
  -n opentelemetry --timeout=180s
kubectl rollout status deployment/inventory-service \
  -n opentelemetry --timeout=180s
kubectl rollout status deployment/otel-demo \
  -n opentelemetry --timeout=180s

log "Checking Kubernetes resources"
kubectl get pods -n elastic
kubectl get pods -n monitoring
kubectl get pods -n logging
kubectl get pods -n opentelemetry
kubectl get ingress -A

cat <<'EOF'

Setup complete.

Next:
  1. In a second terminal run the Ingress port-forward:
       ./scripts/tunnel.sh

  2. Configure local hostnames:
       sudo ./scripts/hosts.sh

  3. Validate:
       ./scripts/validate.sh

  4. Open:
       http://grafana.local:8080
       http://prometheus.local:8080
       http://elasticsearch.local:8080
       http://jaeger.local:8080
       http://otel-demo.local:8080

Grafana credentials:
  The username/password are managed by the Grafana Helm values/Secret.
  Retrieve the effective values with:
    kubectl get secret grafana -n monitoring \
      -o jsonpath="{.data.admin-user}" | base64 --decode; echo
    kubectl get secret grafana -n monitoring \
      -o jsonpath="{.data.admin-password}" | base64 --decode; echo

Grafana datasources:
  Prometheus   -> application/infrastructure metrics
  VictoriaLogs -> application logs
  Jaeger       -> distributed traces

VictoriaLogs:
  Internal URL:
    http://victoria-logs-victoria-logs-single-server.logging.svc.cluster.local:9428
  Built-in UI (from inside the cluster or via a temporary port-forward):
    /select/vmui

OTel Collector:
  OTLP/gRPC :4317
  OTLP/HTTP  :4318
  Prometheus exporter :8889
  Health check :13133

Browser access uses the Ingress port-forward on localhost:8080.
The Collector and VictoriaLogs are internal services reached through Kubernetes DNS.
EOF
