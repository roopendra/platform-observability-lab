# Platform Observability Lab

A reproducible **macOS + Docker Desktop + Minikube** playground for learning practical Platform Engineering observability.

## What this lab covers

- Kubernetes on Minikube
- NGINX Ingress and local browser access
- Elasticsearch infrastructure monitoring
- Elasticsearch Exporter → Prometheus → Grafana
- OpenTelemetry Python instrumentation
- OpenTelemetry Collector
- Kubernetes metadata enrichment
- Application metrics → Prometheus
- Application logs → VictoriaLogs
- Distributed traces → Jaeger
- Trace context propagation across 3 services
- Success and failure tracing / failure localization
- Trace IDs and span IDs in application logs
- Logs ↔ metrics ↔ traces investigation workflow

### Final architecture

```text
                           ┌──────────────► Prometheus ─────► Grafana
                           │
3-service demo ── OTLP ──► OTel Collector
                           │
                           ├── logs ──────► VictoriaLogs ───► Grafana
                           │
                           └── traces ────► Jaeger ─────────► Jaeger UI

Elasticsearch ──► Elasticsearch Exporter ──► Prometheus ──► Grafana
```

> **Scope:** local learning/dev environment, not production.
>
> Jaeger uses in-memory storage, so traces disappear when Jaeger restarts. VictoriaLogs uses 7-day retention and no persistent volume for this lab.

---

# 1. Prerequisites

This lab is validated on macOS.

Install:

| Tool | Purpose |
|---|---|
| Docker Desktop | Container runtime |
| kubectl | Kubernetes CLI |
| Minikube | Local Kubernetes |
| Helm | Install platform components |
| Python 3 | Optional local demo development |

Check:

```bash
docker --version
kubectl version --client
minikube version
helm version
python3 --version
```

Docker Desktop must be running. `start.sh` will try to start it automatically on macOS.

### Versions used during validation

- Minikube `1.38.1`
- Kubernetes `1.35.1`
- Docker `29.2.1`
- Elasticsearch `8.15.0`
- Prometheus Helm chart `29.27.0`
- Grafana Helm chart `10.5.15`
- Elasticsearch Exporter Helm chart `7.4.0`
- OTel Collector Helm chart `0.172.1`
- OTel Collector `0.159.0`
- VictoriaLogs Helm chart `0.13.9`
- VictoriaLogs `1.52.0`
- VictoriaLogs Grafana plugin `0.31.0`
- Jaeger `2.20.0`

---

# 2. Setup the lab

Clone your repository:

```bash
git clone <your-platform-observability-lab-repo-url>
cd platform-observability-lab
```

Make scripts executable:

```bash
chmod +x scripts/*.sh
```

Start everything:

```bash
./scripts/start.sh
```

`start.sh` creates the complete lab:

1. Docker / Minikube
2. NGINX Ingress
3. Elasticsearch
4. Prometheus
5. Grafana
6. Elasticsearch Exporter
7. VictoriaLogs
8. OpenTelemetry Collector
9. Jaeger
10. `otel-demo`
11. `user-service`
12. `inventory-service`
13. All required Ingress resources

Check:

```bash
kubectl get pods -A
```

---

# 3. Enable browser access

With Minikube's Docker driver on macOS, use the tunnel.

Open a second terminal:

```bash
cd platform-observability-lab
./scripts/tunnel.sh
```

Keep it running.

In another terminal:

```bash
sudo ./scripts/hosts.sh
```

The helper configures:

```text
127.0.0.1 grafana.local
127.0.0.1 prometheus.local
127.0.0.1 elasticsearch.local
127.0.0.1 jaeger.local
127.0.0.1 otel-demo.local
```

Normal browser usage does **not** require port-forwarding.

---

# 4. Validate the lab

Run:

```bash
./scripts/validate.sh
```

Quick overview:

```bash
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
```

Check resources if the machine feels slow:

```bash
kubectl top node
kubectl top pods -A
```

---

# 5. Generate dummy telemetry

The easiest way to exercise the complete platform:

```bash
./scripts/generate-data.sh
```

It generates:

- successful distributed `/api` requests
- failed `/api?fail_inventory=true` requests
- direct `/error` requests

The script uses:

```text
http://otel-demo.local
```

So start the tunnel and configure `/etc/hosts` first.

You can also generate individual requests:

### Success

```bash
curl -s http://otel-demo.local/api
```

### Failure

```bash
curl -s "http://otel-demo.local/api?fail_inventory=true"
```

Expected failure path:

```text
otel-demo              502
 ├── user-service      200
 └── inventory-service 500
```

### Direct application error

```bash
curl -s http://otel-demo.local/error
```

---

# 6. Explore the telemetry

## Grafana

Open:

```text
http://grafana.local
```

Fresh lab credentials:

```text
admin / admin
```

If an existing Helm release has a different password:

```bash
kubectl get secret grafana -n monitoring   -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

Grafana has these datasources:

- Prometheus
- VictoriaLogs
- Jaeger

---

## Prometheus

Open:

```text
http://prometheus.local
```

Try:

```promql
up
```

```promql
app_requests_total
```

```promql
sum(rate(app_requests_total[5m]))
```

Elasticsearch exporter:

```promql
up{job="elasticsearch-exporter"}
```

Collector application metrics:

```promql
up{job="otel-collector"}
```

---

## Jaeger

Open:

```text
http://jaeger.local
```

Select service:

```text
otel-demo
```

A successful request should look like:

```text
otel-demo
└── GET /api
    └── process-api-request
        ├── user-service
        │   └── fetch-user
        └── inventory-service
            └── check-inventory
```

This is one distributed trace across all three services.

Now run:

```bash
curl -s "http://otel-demo.local/api?fail_inventory=true"
```

The trace should identify:

```text
inventory-service
└── check-inventory
    ERROR
```

while the parent `otel-demo` request returns `502`.

---

## VictoriaLogs

Open:

```text
http://grafana.local
```

Then:

```text
Explore → VictoriaLogs
```

Look for fields such as:

```text
service.name
trace_id
span_id
k8s.namespace.name
k8s.pod.name
k8s.deployment.name
k8s.container.name
```

The practical workflow is:

```text
Log error
   ↓
trace_id
   ↓
Jaeger trace
   ↓
Find slow/failing service
   ↓
Return to logs for application context
```

---

# 7. What the demo application does

The demo is intentionally small:

```text
                  ┌────────────────┐
                  │   otel-demo    │
                  │      :8080     │
                  └───────┬────────┘
                          │
                 ┌────────┴────────┐
                 ▼                 ▼
        ┌────────────────┐  ┌────────────────────┐
        │  user-service  │  │ inventory-service  │
        │     :8081      │  │       :8082        │
        └────────────────┘  └────────────────────┘
```

`/api` calls both downstream services.

`fail_inventory=true` intentionally makes `inventory-service` fail. This makes the distributed trace useful for demonstrating blast-radius/failure localization.

All three services send telemetry to the Collector using OTLP.

---

# 8. Collector pipelines

The Collector is the central telemetry routing layer:

```text
Application
    │
    ▼
OTel Collector
    ├── logs    → VictoriaLogs
    ├── metrics → Prometheus
    └── traces  → Jaeger
```

Applications use the internal Kubernetes endpoint:

```text
opentelemetry-collector.opentelemetry.svc.cluster.local:4318
```

Important ports:

| Port | Purpose |
|---:|---|
| 4317 | OTLP/gRPC |
| 4318 | OTLP/HTTP |
| 8889 | Prometheus exporter |
| 13133 | Health check |

The Collector also adds Kubernetes metadata using `k8sattributes`, for example:

```text
k8s.namespace.name
k8s.pod.name
k8s.pod.uid
k8s.node.name
k8s.deployment.name
k8s.container.name
```

---

# 9. Repository layout

```text
platform-observability-lab/
├── README.md
├── VERSION
├── namespaces.yaml
├── elasticsearch/
├── monitoring/
├── logging/
├── opentelemetry/
├── tracing/
├── otel-demo/
│   ├── app.py
│   ├── deployment.yaml
│   ├── ingress.yaml
│   ├── user-service/
│   └── inventory-service/
├── dashboards/
├── docs/
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

# 10. Useful scripts

| Script | Purpose |
|---|---|
| `start.sh` | Start/recreate all lab workloads |
| `generate-data.sh` | Generate success/error telemetry |
| `validate.sh` | Validate the environment |
| `tunnel.sh` | Start Minikube tunnel |
| `hosts.sh` | Configure `/etc/hosts` |
| `stop.sh` | Stop Minikube without deleting the cluster |
| `uninstall.sh` | Remove lab workloads but keep Minikube |
| `reset.sh` | Delete Minikube and rebuild from scratch |

### Stop

```bash
./scripts/stop.sh
```

### Start again

```bash
./scripts/start.sh
```

### Remove workloads

```bash
./scripts/uninstall.sh
```

### Full clean-room reset

```bash
./scripts/reset.sh
```

`reset.sh` is useful when you want to prove the repository can reproduce the lab from a clean Minikube cluster.

---

# 11. Browser URLs

| Component | URL |
|---|---|
| Grafana | http://grafana.local |
| Prometheus | http://prometheus.local |
| Elasticsearch | http://elasticsearch.local |
| Jaeger | http://jaeger.local |
| Demo application | http://otel-demo.local |

VictoriaLogs and the Collector are internal Kubernetes services.

---

# 12. Troubleshooting

Start with:

```bash
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
kubectl top node
kubectl top pods -A
```

Collector:

```bash
kubectl logs -n opentelemetry deployment/opentelemetry-collector --since=10m
```

Jaeger:

```bash
kubectl logs -n opentelemetry deployment/jaeger --tail=100
```

VictoriaLogs:

```bash
kubectl logs -n logging   -l app.kubernetes.io/instance=victoria-logs   --tail=100
```

Demo services:

```bash
kubectl logs -n opentelemetry deployment/otel-demo --tail=100
kubectl logs -n opentelemetry deployment/user-service --tail=100
kubectl logs -n opentelemetry deployment/inventory-service --tail=100
```

If `.local` URLs do not work:

```bash
grep -E 'grafana\.local|prometheus\.local|elasticsearch\.local|jaeger\.local|otel-demo\.local' /etc/hosts
```

Then:

```bash
minikube status
kubectl get pods -n ingress-nginx
kubectl get ingress -A
```

Restart the tunnel if required:

```bash
minikube tunnel --cleanup
./scripts/tunnel.sh
```

More detailed troubleshooting is in:

```text
docs/troubleshooting.md
```

---

# 13. Production note

This lab intentionally avoids turning tracing into another large production datastore.

Jaeger uses memory storage here. A production implementation would normally require:

```text
OTel Collector
      ↓
sampling / filtering
      ↓
persistent trace backend
      ↓
Jaeger
```

Before adding persistent trace storage, measure:

- requests/sec
- spans/request
- trace volume
- retention
- query workload
- percentage of errors/slow traces

Then design sampling and retention around actual value and cost.

---

# 14. 30-second quick start

If you only want the commands:

```bash
git clone <your-platform-observability-lab-repo-url>
cd platform-observability-lab
chmod +x scripts/*.sh
./scripts/start.sh
```

Second terminal:

```bash
./scripts/tunnel.sh
```

Third terminal:

```bash
sudo ./scripts/hosts.sh
./scripts/validate.sh
./scripts/generate-data.sh
```

Open:

```text
http://grafana.local
http://jaeger.local
http://otel-demo.local
```

Run the failure demo:

```bash
curl -s "http://otel-demo.local/api?fail_inventory=true"
```

Then follow:

```text
VictoriaLogs → trace_id → Jaeger → failing service
```

**That's the lab.**
