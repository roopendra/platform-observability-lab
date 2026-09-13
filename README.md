# Platform Observability Lab

A reproducible local Kubernetes observability playground for **macOS and Linux** using Minikube and the Docker driver.

This lab demonstrates:

- Kubernetes + NGINX Ingress
- Elasticsearch infrastructure monitoring
- Prometheus + Grafana
- OpenTelemetry SDKs + Collector
- Kubernetes metadata enrichment
- Distributed tracing with Jaeger
- Application logs in VictoriaLogs
- Application metrics in Prometheus
- Logs ↔ traces correlation
- A small three-service Python/Flask application with success and failure scenarios

> **Scope:** This is a local learning/development environment, not a production architecture.
>
> Jaeger uses in-memory storage, so traces are lost when Jaeger restarts. VictoriaLogs uses 7-day retention with persistent storage disabled.

---

## Architecture

### Application telemetry

```text
                       OpenTelemetry
                            │
                 ┌──────────┴──────────┐
                 │      Collector      │
                 │                     │
                 ├── logs ───────────► VictoriaLogs
                 ├── metrics ─────────► Prometheus
                 └── traces ──────────► Jaeger
                                           │
                                           ▼
                                       Jaeger UI
```

### Application

```text
                         otel-demo
                            │
                 ┌──────────┴──────────┐
                 ▼                     ▼
          user-service        inventory-service
             :8081                   :8082
```

All three services are instrumented with OpenTelemetry and propagate distributed trace context.

### Elasticsearch monitoring

```text
Elasticsearch
      │
      ▼
ES Exporter
      │
      ▼
Prometheus
      │
      ▼
Grafana
```

Elasticsearch is used only for infrastructure monitoring. It is **not** the application log backend.

---

## Quick start

### 1. Prerequisites

Install:

- Docker / Docker Desktop
- Minikube
- kubectl
- Helm
- Python 3

Check:

```bash
docker --version
kubectl version --client
minikube version
helm version
python3 --version
```

The lab uses the Minikube Docker driver:

```bash
minikube start --driver=docker
```

`start.sh` handles Minikube startup automatically.

### 2. Start the lab

From the repository root:

```bash
chmod +x scripts/*.sh
./scripts/start.sh
```

The script installs/deploys:

- Minikube + NGINX Ingress
- Elasticsearch
- Prometheus
- Grafana
- Elasticsearch exporter
- VictoriaLogs
- OpenTelemetry Collector
- Jaeger
- Three demo services

### 3. Configure browser access

The lab uses local hostnames:

```text
grafana.local
prometheus.local
elasticsearch.local
jaeger.local
otel-demo.local
```

Add them to `/etc/hosts`:

```bash
sudo ./scripts/hosts.sh
```

#### macOS

With Minikube + Docker driver, browser access normally requires the Minikube tunnel.

Run in a second terminal:

```bash
./scripts/tunnel.sh
```

Keep the tunnel terminal running.

#### Linux

The exact networking behavior depends on the Docker/Minikube environment. If the browser-facing Ingress is not reachable directly, use:

```bash
./scripts/tunnel.sh
```

The normal application workflow does **not** require `kubectl port-forward`.

### 4. Validate

```bash
./scripts/validate.sh
```

### 5. Generate telemetry

```bash
./scripts/generate-data.sh
```

Or generate individual scenarios:

```bash
# Successful distributed request
curl -s http://otel-demo.local/api

# Downstream failure
curl -s "http://otel-demo.local/api?fail_inventory=true"

# Direct application error
curl -s http://otel-demo.local/error
```

---

## Browser URLs

With `/etc/hosts` configured and Ingress networking working:

| Component | URL |
|---|---|
| Grafana | http://grafana.local |
| Prometheus | http://prometheus.local |
| Elasticsearch | http://elasticsearch.local |
| Jaeger | http://jaeger.local |
| Demo application | http://otel-demo.local |

Grafana is configured with:

- Prometheus
- VictoriaLogs
- Jaeger

Fresh Grafana installations use:

```text
admin / admin
```

For an existing installation, retrieve the actual credentials:

```bash
kubectl get secret grafana -n monitoring \
  -o jsonpath="{.data.admin-user}" | base64 --decode; echo

kubectl get secret grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

Do not commit real credentials to source control.

---

## What to verify

### 1. Distributed tracing

Generate:

```bash
curl -s http://otel-demo.local/api
```

Open Jaeger:

```text
http://jaeger.local
```

Search for service:

```text
otel-demo
```

A successful request should show one distributed trace containing:

```text
otel-demo
└── GET /api
    └── process-api-request
        ├── user-service
        │   └── fetch-user
        └── inventory-service
            └── check-inventory
```

### 2. Failure propagation

Run:

```bash
curl -s "http://otel-demo.local/api?fail_inventory=true"
```

Expected high-level result:

```text
otel-demo                  502
    │
    ├── user-service       200
    │
    └── inventory-service  500
```

Jaeger should show the downstream inventory operation and its parent request marked as errors.

### 3. Application logs

Open:

```text
http://grafana.local
```

Go to:

```text
Explore → VictoriaLogs
```

Generate traffic first:

```bash
./scripts/generate-data.sh
```

Useful searches include:

```text
service.name:otel-demo
```

and:

```text
trace_id
```

Application logs include trace and span context, allowing an operational workflow such as:

```text
Log error
   ↓
Read trace_id
   ↓
Open trace
   ↓
Find slow/failing service
   ↓
Return to logs for application context
```

### 4. Application metrics

In Grafana or Prometheus, try:

```promql
app_requests_total
```

and:

```promql
sum(rate(app_requests_total[5m]))
```

The application metric path is:

```text
Application
    │ OTLP
    ▼
OTel Collector
    │ Prometheus exporter :8889
    ▼
Prometheus
    ▼
Grafana
```

### 5. Elasticsearch metrics

In Prometheus, try:

```promql
up{job="elasticsearch-exporter"}
```

and:

```promql
up{job="otel-collector"}
```

Useful Elasticsearch metrics include:

```text
elasticsearch_cluster_health_status
elasticsearch_jvm_memory_used_bytes
elasticsearch_indices_docs
```

---

## Grafana dashboards

The repository includes:

```text
dashboards/elasticsearch-cluster-overview.json
dashboards/otel-demo-application-overview.json
```

Import the application dashboard through:

```text
Grafana → Dashboards → Import
```

Select the existing Prometheus datasource.

Generate traffic:

```bash
./scripts/generate-data.sh
```

---

## Components and namespaces

| Namespace | Components |
|---|---|
| `elastic` | Elasticsearch |
| `monitoring` | Prometheus, Grafana, Elasticsearch exporter |
| `logging` | VictoriaLogs |
| `opentelemetry` | OTel Collector, Jaeger, demo services |
| `ingress-nginx` | NGINX Ingress |

The Collector is internal-only. Applications send OTLP to:

```text
opentelemetry-collector.opentelemetry.svc.cluster.local:4318
```

Important Collector ports:

| Port | Purpose |
|---:|---|
| 4317 | OTLP/gRPC |
| 4318 | OTLP/HTTP |
| 8889 | Prometheus exporter |
| 13133 | Health check |

The Collector uses the `k8sattributes` preset to enrich telemetry with Kubernetes metadata such as:

```text
k8s.namespace.name
k8s.pod.name
k8s.pod.uid
k8s.node.name
k8s.deployment.name
k8s.container.name
```

---

## Version pins

The reproducible scripts currently use:

| Component | Version |
|---|---|
| Elasticsearch | 8.15.0 |
| Prometheus Helm chart | 29.27.0 |
| Grafana Helm chart | 10.5.15 |
| Elasticsearch exporter Helm chart | 7.4.0 |
| OpenTelemetry Collector Helm chart | 0.172.1 |
| OTel Collector image | `otel/opentelemetry-collector-contrib:0.159.0` |
| VictoriaLogs Helm chart | 0.13.9 |
| VictoriaLogs | 1.52.0 |
| VictoriaLogs Grafana plugin | 0.31.0 |
| Jaeger | 2.20.0 |
| Python demo | 3.12 |

The lab was validated with Minikube 1.38.1, Kubernetes 1.35.1 and Docker 29.2.1.

---

## Repository layout

```text
platform-observability-lab/
├── README.md
├── VERSION
├── namespaces.yaml
│
├── elasticsearch/
│   ├── es-master.yaml
│   ├── es-data.yaml
│   ├── es-service.yaml
│   └── es-ingress.yaml
│
├── monitoring/
│   ├── prometheus.yaml
│   ├── grafana.yaml
│   ├── elasticsearch-exporter-values.yaml
│   └── monitoring-ingress.yaml
│
├── logging/
│   └── victoria-logs-values.yaml
│
├── opentelemetry/
│   └── collector-values.yaml
│
├── tracing/
│   ├── jaeger.yaml
│   └── jaeger-ingress.yaml
│
├── otel-demo/
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   ├── deployment.yaml
│   ├── ingress.yaml
│   ├── README.md
│   ├── user-service/
│   └── inventory-service/
│
├── dashboards/
│   ├── elasticsearch-cluster-overview.json
│   └── otel-demo-application-overview.json
│
├── docs/
│   └── troubleshooting.md
│
└── scripts/
    ├── start.sh
    ├── generate-data.sh
    ├── validate.sh
    ├── tunnel.sh
    ├── hosts.sh
    ├── stop.sh
    ├── uninstall.sh
    └── reset.sh
```

---

## Day-to-day commands

### Start

```bash
./scripts/start.sh
```

### Generate test telemetry

```bash
./scripts/generate-data.sh
```

Environment variables can be used to change the generated traffic:

```bash
SUCCESS_COUNT=50 FAILURE_COUNT=10 ERROR_COUNT=10 ./scripts/generate-data.sh
```

### Validate

```bash
./scripts/validate.sh
```

### Tunnel

```bash
./scripts/tunnel.sh
```

### Configure hosts

```bash
sudo ./scripts/hosts.sh
```

### Stop

```bash
./scripts/stop.sh
```

Stops Minikube while keeping the cluster state.

### Uninstall workloads

```bash
./scripts/uninstall.sh
```

Removes the main lab workloads/namespaces but keeps Minikube.

### Full reset

```bash
./scripts/reset.sh
```

Deletes the Minikube profile and recreates the lab from scratch.

This removes:

- Kubernetes resources
- Elasticsearch storage
- VictoriaLogs local storage
- transient Jaeger traces
- other local lab state

---

## Troubleshooting

### Browser cannot reach `.local` URLs

Check hosts:

```bash
grep -E 'grafana\.local|prometheus\.local|elasticsearch\.local|jaeger\.local|otel-demo\.local' /etc/hosts
```

Check Minikube and Ingress:

```bash
minikube status
kubectl get pods -n ingress-nginx
kubectl get ingress -A
```

If using a Docker-based Minikube environment, start the tunnel:

```bash
./scripts/tunnel.sh
```

### Grafana shows no application data

Check:

```promql
up
```

Then:

```promql
app_requests_total
```

Generate traffic:

```bash
./scripts/generate-data.sh
```

Check Grafana resources:

```bash
kubectl top pod -n monitoring -l app.kubernetes.io/name=grafana
```

### Collector is running but application metrics are missing

Check the Collector:

```bash
kubectl logs -n opentelemetry deployment/opentelemetry-collector --since=10m
```

Check its Service:

```bash
kubectl get svc opentelemetry-collector -n opentelemetry
```

Remember:

```text
8888 = Collector internal telemetry metrics
8889 = Prometheus exporter for application metrics
```

### Traces reach Collector but not Jaeger

Check:

```bash
kubectl logs -n opentelemetry deployment/opentelemetry-collector --since=10m
```

The trace pipeline should export to Jaeger using:

```yaml
otlp_grpc:
  endpoint: jaeger.opentelemetry.svc.cluster.local:4317
  tls:
    insecure: true
```

### Logs are missing from VictoriaLogs

Check Collector logs:

```bash
kubectl logs -n opentelemetry deployment/opentelemetry-collector --since=10m
```

Check VictoriaLogs:

```bash
kubectl logs -n logging \
  -l app.kubernetes.io/instance=victoria-logs \
  --tail=100
```

The Collector sends logs to:

```text
http://victoria-logs-victoria-logs-single-server.logging.svc.cluster.local:9428/insert/opentelemetry/v1/logs
```

### General Kubernetes overview

```bash
kubectl get nodes
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
kubectl top node
kubectl top pods -A
```

---

## Manual demo image rebuild

`start.sh` builds the application images automatically.

To rebuild manually:

```bash
eval "$(minikube docker-env -p minikube)"

docker build -t otel-demo:1.2 otel-demo/
docker build -t otel-user-service:1.0 otel-demo/user-service/
docker build -t otel-inventory-service:1.0 otel-demo/inventory-service/
```

Then redeploy:

```bash
kubectl apply -f otel-demo/user-service/deployment.yaml
kubectl apply -f otel-demo/inventory-service/deployment.yaml
kubectl apply -f otel-demo/deployment.yaml
kubectl apply -f otel-demo/ingress.yaml
```

---

## Production direction

This lab intentionally keeps the architecture small.

A production evolution would typically add:

```text
Application
    │
    ▼
OTel Collector
    ├──► Metrics backend
    ├──► VictoriaLogs
    └──► Persistent trace backend
                 │
                 ▼
              Jaeger
```

Before introducing persistent tracing, evaluate:

- requests/sec
- spans/request
- bytes/span
- traces/day
- retention
- query workload
- error/slow-trace percentage

Then apply an intentional sampling strategy.

For example:

```text
100% of errors
100% of critical/very slow traces
small percentage of normal successful traffic
short trace retention
```

The important takeaway from this lab is the telemetry model:

```text
                    ┌──► Metrics backend
                    │
Application ──► OTel Collector ──► Logs backend
                    │
                    └──► Trace backend
```

Applications only need to know the OTLP endpoint. The Collector becomes the control point for routing, batching, memory protection, Kubernetes metadata enrichment and future processing.

---

## Lab conclusion

This playground provides an end-to-end Platform Engineering observability workflow:

```text
Application
    │
    ▼
OpenTelemetry Collector
    ├── Logs ────► VictoriaLogs ──► Grafana
    ├── Metrics ─► Prometheus ────► Grafana
    └── Traces ──► Jaeger ────────► Jaeger UI
```

plus:

```text
Elasticsearch ──► ES Exporter ──► Prometheus ──► Grafana
```

It is designed to be easy to start locally, demonstrate the three observability signals, reproduce failure scenarios, and provide a foundation for later production-oriented discussions around sampling, retention, persistence and cost.
