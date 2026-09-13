# Local Platform Engineering Observability Playground

A reproducible **macOS + Docker Desktop + Minikube** lab for learning and demonstrating:

- Kubernetes on Minikube
- NGINX Ingress
- Elasticsearch infrastructure monitoring
- Prometheus + Grafana
- OpenTelemetry instrumentation and Collector pipelines
- Kubernetes metadata enrichment
- Distributed tracing with Jaeger
- Application logs in VictoriaLogs
- Application metrics in Prometheus
- Logs ↔ traces correlation in Grafana
- A small 3-service Python/Flask application that produces realistic success and failure traces

> **Scope:** this is a local learning/dev environment, not a production architecture.
>
> The lab intentionally keeps Jaeger on transient in-memory storage. That lets us learn tracing without introducing another persistent production-sized datastore just for the lab. Trace data disappears when Jaeger restarts.
>
> VictoriaLogs is configured with **7-day retention** and no persistent volume so a full Minikube reset remains a clean-room reset.

---

## 1. Final architecture

The lab is now a complete three-signal observability path:

```text
                         macOS
                           │
                  /etc/hosts + tunnel
                           │
                           ▼
                     NGINX Ingress
          ┌────────────────┼─────────────────┐
          │                │                 │
          ▼                ▼                 ▼
      Grafana         Prometheus          Jaeger
          │                ▲                 │
          │                │                 │
          │          application metrics     │ traces
          │                │                 │
          │                │                 │
          ├──────────────► VictoriaLogs ◄────┤
          │                    ▲
          │                    │ application logs
          │                    │
          │             OTel Collector
          │              ▲     ▲     ▲
          │              │     │     │
          │           OTLP   OTLP   OTLP
          │              │     │     │
          │              └─────┴─────┘
          │                    │
          │              Distributed app
          │        ┌───────────┼───────────┐
          │        │           │           │
          │     otel-demo   user-service  inventory-service
          │
          │
          └── Grafana queries:
              Prometheus + VictoriaLogs + Jaeger


Infrastructure monitoring path:

Elasticsearch
      │
      ▼
Elasticsearch Exporter
      │
      ▼
Prometheus
      │
      ▼
Grafana
```

### Signal ownership

| Signal | Collection | Storage/backend | Visualization |
|---|---|---|---|
| Metrics | OTel Collector | Prometheus | Grafana |
| Traces | OTel Collector | Jaeger memory store | Jaeger UI / Grafana |
| Application logs | OTel SDK → Collector | VictoriaLogs | Grafana Explore |
| Elasticsearch metrics | Elasticsearch exporter | Prometheus | Grafana |
| Kubernetes metadata | OTel Collector `k8sattributes` | Added to telemetry | All applicable backends |

The key design principle is:

```text
Application
    │
    ▼
OpenTelemetry Collector
    ├── logs    ──► VictoriaLogs
    ├── metrics ──► Prometheus
    └── traces  ──► Jaeger
```

The applications do **not** need to know the final observability backend for every signal.

---

# 2. What this lab demonstrates

By the end of the lab you can demonstrate:

1. Elasticsearch cluster monitoring with Prometheus.
2. Grafana dashboards backed by Prometheus.
3. OpenTelemetry SDK instrumentation in Python.
4. OTLP/HTTP ingestion into the Collector.
5. Kubernetes metadata enrichment.
6. Application metrics through the Collector → Prometheus exporter.
7. Distributed tracing across three services.
8. Error propagation across service boundaries.
9. Application logs through OTLP → Collector → VictoriaLogs.
10. Trace IDs and span IDs appearing in application logs.
11. Grafana access to Prometheus, VictoriaLogs and Jaeger.
12. A practical logs/metrics/traces workflow.

---

# 3. Repository layout

```text
elasticsearch-monitoring-minikube/
├── README.md
├── VERSION
├── .gitignore
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
│   │
│   ├── user-service/
│   │   ├── app.py
│   │   ├── requirements.txt
│   │   ├── Dockerfile
│   │   └── deployment.yaml
│   │
│   └── inventory-service/
│       ├── app.py
│       ├── requirements.txt
│       ├── Dockerfile
│       └── deployment.yaml
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
    ├── stop.sh
    ├── reset.sh
    ├── tunnel.sh
    ├── hosts.sh
    ├── validate.sh
    └── uninstall.sh
```

---

# 4. Versions used by the lab

The version pins below are the versions used by the reproducible scripts.

| Component | Version |
|---|---|
| Elasticsearch | 8.15.0 |
| Prometheus Helm chart | 29.27.0 |
| Grafana Helm chart | 10.5.15 |
| Elasticsearch exporter Helm chart | 7.4.0 |
| OpenTelemetry Collector Helm chart | 0.172.1 |
| OpenTelemetry Collector image | `otel/opentelemetry-collector-contrib:0.159.0` |
| VictoriaLogs Helm chart | 0.13.9 |
| VictoriaLogs application | 1.52.0 |
| VictoriaLogs Grafana plugin | 0.31.0 |
| Jaeger | 2.20.0 |
| Python demo | 3.12 |
| Minikube | 1.38.1 was used during lab validation |
| Kubernetes | 1.35.1 was used during lab validation |
| Docker | 29.2.1 was used during lab validation |

Check your installed tools:

```bash
docker --version
kubectl version --client
minikube version
helm version
python3 --version
```

---

# 5. Prerequisites

Install:

- Docker Desktop
- kubectl
- Minikube
- Helm
- Python 3

On macOS:

```bash
open -a Docker
```

Wait until:

```bash
docker info
```

works successfully.

The lab uses the Minikube Docker driver:

```bash
minikube start --driver=docker
```

The `start.sh` script performs this step automatically.

---

# 6. One-command startup

From the repository root:

```bash
chmod +x scripts/*.sh
./scripts/start.sh
```

The script:

1. Starts Docker Desktop if required.
2. Starts Minikube with the Docker driver.
3. Enables NGINX Ingress.
4. Creates all required namespaces.
5. Deploys Elasticsearch.
6. Installs Prometheus.
7. Installs Grafana.
8. Installs the Elasticsearch exporter.
9. Installs VictoriaLogs.
10. Installs the OpenTelemetry Collector.
11. Deploys Jaeger.
12. Builds all three demo application images inside Minikube.
13. Deploys the three application services.
14. Applies all Ingress resources.
15. Waits for the workloads to become ready.
16. Prints the next steps.

No application-specific `kubectl port-forward` is required for normal browser access.

---

# 7. Namespaces

The final lab uses:

| Namespace | Purpose |
|---|---|
| `elastic` | Elasticsearch |
| `monitoring` | Prometheus, Grafana, Elasticsearch exporter |
| `logging` | VictoriaLogs |
| `opentelemetry` | Collector, Jaeger, demo services |
| `ingress-nginx` | Minikube NGINX Ingress |

Verify:

```bash
kubectl get namespaces
```

---

# 8. Elasticsearch

Elasticsearch remains in the lab for **infrastructure monitoring**.

It is not the application's log backend anymore.

The cluster contains:

```text
es-master-0
es-data-0
```

Check:

```bash
kubectl get pods -n elastic
kubectl get statefulsets -n elastic
kubectl get pvc -n elastic
```

The lab uses:

```text
cluster.name = test-es-cluster
xpack.security.enabled = false
```

This is intentionally simplified for local development.

---

# 9. Elasticsearch Services

Two Services are used.

### Headless transport/discovery

```text
elasticsearch.elastic.svc.cluster.local:9300
```

### Stable HTTP API

```text
elasticsearch-client.elastic.svc.cluster.local:9200
```

Test the API from Kubernetes:

```bash
kubectl run curl-es \
  -n monitoring \
  --image=curlimages/curl:8.10.1 \
  --restart=Never \
  --rm -it \
  -- \
  curl -s http://elasticsearch-client.elastic.svc.cluster.local:9200
```

---

# 10. Prometheus

This lab intentionally uses the regular:

```text
prometheus-community/prometheus
```

Helm chart.

It does **not** use Prometheus Operator.

Therefore the Elasticsearch exporter and Collector are configured through `extraScrapeConfigs`.

Prometheus scrapes:

```text
Elasticsearch Exporter :9108
OTel Collector         :8889
```

The application metrics path is:

```text
Application
    │ OTLP
    ▼
OTel Collector
    │
    ▼
Prometheus exporter :8889
    │
    ▼
Prometheus
```

Useful checks:

```bash
kubectl get pods -n monitoring
helm status prometheus -n monitoring
```

Prometheus URL:

```text
http://prometheus.local
```

Useful PromQL:

```promql
up{job="elasticsearch-exporter"}
```

```promql
up{job="otel-collector"}
```

```promql
app_requests_total
```

```promql
sum(rate(app_requests_total[5m]))
```

---

# 11. Elasticsearch exporter

The exporter connects to:

```text
http://elasticsearch-client.elastic.svc.cluster.local:9200
```

Important configuration:

```yaml
es:
  uri: http://elasticsearch-client.elastic.svc.cluster.local:9200
  all: true
  indices: true
  indices_settings: true
  indices_mappings: true
  shards: true
  snapshots: true
  cluster_settings: false
  timeout: 30s
```

Test:

```bash
kubectl run exporter-check \
  -n monitoring \
  --image=curlimages/curl:8.10.1 \
  --restart=Never \
  --rm -it \
  -- \
  curl -s http://elasticsearch-exporter-prometheus-elasticsearch-exporter:9108/metrics
```

Look for:

```text
elasticsearch_cluster_health_status
elasticsearch_jvm_memory_used_bytes
elasticsearch_indices_docs
```

---

# 12. Grafana

Grafana is configured automatically with three datasources.

### Prometheus

```text
http://prometheus-server.monitoring.svc.cluster.local:80
```

### Jaeger

```text
http://jaeger.opentelemetry.svc.cluster.local:16686
```

### VictoriaLogs

```text
http://victoria-logs-victoria-logs-single-server.logging.svc.cluster.local:9428
```

The VictoriaLogs datasource plugin is installed automatically:

```text
victoriametrics-logs-datasource 0.31.0
```

The Grafana configuration also enables the VictoriaLogs OpenTelemetry preset and points trace navigation to the Jaeger datasource.

Open:

```text
http://grafana.local
```

---

## 12.1 Grafana credentials

The lab values use:

```text
admin / admin
```

for a fresh installation.

For an existing Helm release, always retrieve the actual Secret:

```bash
kubectl get secret grafana \
  -n monitoring \
  -o jsonpath="{.data.admin-user}" | base64 --decode; echo
```

```bash
kubectl get secret grafana \
  -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

Do not commit real credentials to source control.

---

# 13. Grafana resources

Grafana was previously limited to 256Mi and became unstable during dashboard usage.

The final lab uses:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

Check:

```bash
kubectl top pod -n monitoring -l app.kubernetes.io/name=grafana
```

If Grafana becomes slow:

```bash
kubectl describe pod -n monitoring \
  -l app.kubernetes.io/name=grafana
```

---

# 14. VictoriaLogs

VictoriaLogs is now the application's log backend.

```text
Application
    │
    │ OTLP/HTTP logs
    ▼
OTel Collector
    │
    │ otlp_http/victorialogs
    ▼
VictoriaLogs :9428
    │
    ▼
Grafana Explore
```

The internal Service is:

```text
victoria-logs-victoria-logs-single-server.logging.svc.cluster.local:9428
```

The lab configures:

```text
Retention: 7 days
Persistent volume: disabled
```

This is deliberate for a local playground.

Check:

```bash
kubectl get pods -n logging
kubectl get svc -n logging
helm status victoria-logs -n logging
```

---

## 14.1 VictoriaLogs UI

VictoriaLogs has its own UI at:

```text
/select/vmui
```

The lab does not create a host-facing Ingress for VictoriaLogs because Grafana is the normal user-facing log UI.

If you need the built-in UI temporarily:

```bash
kubectl port-forward \
  -n logging \
  svc/victoria-logs-victoria-logs-single-server \
  9428:9428
```

Then open:

```text
http://localhost:9428/select/vmui
```

Port-forwarding is optional and only for direct VictoriaLogs troubleshooting.

---

# 15. OpenTelemetry Collector

The Collector is the central telemetry pipeline.

The lab uses the **contrib** distribution because the required exporters/processors are not all present in the minimal distribution.

Image:

```text
otel/opentelemetry-collector-contrib:0.159.0
```

Important ports:

| Port | Purpose |
|---:|---|
| 4317 | OTLP/gRPC |
| 4318 | OTLP/HTTP |
| 8889 | Prometheus exporter |
| 13133 | Health check |

The Collector is internal-only.

Applications use:

```text
opentelemetry-collector.opentelemetry.svc.cluster.local:4318
```

---

# 16. Collector pipelines

The final Collector has three pipelines.

### Logs

```text
OTLP
  │
  ▼
k8sattributes
  │
  ▼
memory_limiter
  │
  ▼
batch
  │
  ▼
VictoriaLogs
```

### Metrics

```text
OTLP
  │
  ▼
k8sattributes
  │
  ▼
memory_limiter
  │
  ▼
batch
  │
  ▼
Prometheus exporter :8889
  │
  ▼
Prometheus
```

### Traces

```text
OTLP
  │
  ▼
k8sattributes
  │
  ▼
memory_limiter
  │
  ▼
batch
  │
  ├──► debug
  │
  └──► Jaeger
```

The `debug` exporter is useful while learning because it lets us see what the Collector receives.

---

# 17. Kubernetes metadata enrichment

The Collector enables:

```yaml
presets:
  kubernetesAttributes:
    enabled: true
```

This adds Kubernetes metadata such as:

```text
k8s.namespace.name
k8s.pod.name
k8s.pod.uid
k8s.node.name
k8s.deployment.name
k8s.container.name
```

That metadata becomes part of the telemetry context.

For example, a trace can contain:

```text
service.name = otel-demo
k8s.namespace.name = opentelemetry
k8s.pod.name = otel-demo-...
k8s.deployment.name = otel-demo
k8s.node.name = minikube
```

This is one of the most useful Collector capabilities in Kubernetes.

---

# 18. Important Collector configuration detail

The Helm chart has two different concepts.

Kubernetes Service configuration:

```yaml
service:
```

Collector configuration:

```yaml
config:
  service:
    pipelines:
```

Telemetry pipelines must be under:

```yaml
config:
  service:
    pipelines:
```

Putting `pipelines` under the chart's root-level `service` causes Helm schema validation errors.

---

# 19. Collector exporter naming

Use:

```yaml
otlp_grpc:
```

for the Jaeger exporter.

Do not use the old:

```yaml
otlp:
```

name in the version-controlled configuration.

For VictoriaLogs the final configuration uses:

```yaml
otlp_http/victorialogs:
```

with:

```yaml
logs_endpoint: http://victoria-logs-victoria-logs-single-server.logging.svc.cluster.local:9428/insert/opentelemetry/v1/logs
```

---

# 20. Collector health

Check:

```bash
kubectl get pods -n opentelemetry
kubectl logs -n opentelemetry deployment/opentelemetry-collector --tail=50
```

A healthy Collector should eventually report readiness messages.

Check the Service:

```bash
kubectl get svc opentelemetry-collector -n opentelemetry
```

Expected important ports:

```text
13133/TCP
4317/TCP
4318/TCP
8889/TCP
```

---

# 21. Jaeger

Jaeger is the tracing UI/backend for this lab.

Version:

```text
jaegertracing/jaeger:2.20.0
```

Trace flow:

```text
Application
    │
    │ OTLP/HTTP
    ▼
OTel Collector
    │
    │ OTLP/gRPC
    ▼
Jaeger
    │
    ▼
Jaeger UI
```

Jaeger Service:

```text
jaeger.opentelemetry.svc.cluster.local
```

Ports:

```text
16686  UI
4317   OTLP/gRPC
4318   OTLP/HTTP
```

Open:

```text
http://jaeger.local
```

---

## 21.1 Important Jaeger storage decision

This lab uses Jaeger's in-memory storage.

That is intentional.

It avoids adding another persistent datastore just to complete the local tracing exercise.

The consequence is:

```text
Jaeger restart
    ↓
trace data lost
```

That is acceptable for a playground.

It is **not** a production storage model.

For a production tracing platform, the next design decision would be:

```text
OTel Collector
      │
      ▼
sampling / filtering
      │
      ▼
persistent trace backend
      │
      ▼
Jaeger UI
```

The lab deliberately stops before adding that second persistent trace platform.

---

# 22. Distributed demo application

The application was upgraded from a single service to three services.

```text
                         ┌───────────────┐
                         │   otel-demo   │
                         │  service A    │
                         └───────┬───────┘
                                 │
                     ┌───────────┴───────────┐
                     │                       │
                     ▼                       ▼
             ┌───────────────┐      ┌──────────────────┐
             │ user-service  │      │ inventory-service│
             │   :8081       │      │      :8082       │
             └───────────────┘      └──────────────────┘
```

All three services are instrumented with OpenTelemetry.

They send:

```text
traces → Collector
logs   → Collector
```

The parent trace context is propagated between services.

---

# 23. Demo application endpoints

Main application:

```text
/
 /api
 /error
 /health
```

The distributed workflow is:

```text
GET /api
   │
   ├──► user-service /users/123
   │
   └──► inventory-service /inventory/item-001
```

The application adds deliberate latency so the distributed trace is easy to understand.

---

# 24. Build the demo manually

`start.sh` already does this automatically.

If you need to rebuild manually:

```bash
eval "$(minikube docker-env -p minikube)"
```

Build:

```bash
docker build -t otel-demo:1.2 otel-demo/
docker build -t otel-user-service:1.0 otel-demo/user-service/
docker build -t otel-inventory-service:1.0 otel-demo/inventory-service/
```

Deploy:

```bash
kubectl apply -f otel-demo/user-service/deployment.yaml
kubectl apply -f otel-demo/inventory-service/deployment.yaml
kubectl apply -f otel-demo/deployment.yaml
kubectl apply -f otel-demo/ingress.yaml
```

Check:

```bash
kubectl get pods -n opentelemetry
```

---

# 25. Application OTLP configuration

The application receives the Collector endpoint through Kubernetes environment variables.

Example:

```yaml
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: http://opentelemetry-collector.opentelemetry.svc.cluster.local:4318
```

The application code therefore does not depend on:

```text
localhost
```

or a host-facing Collector address.

Verify:

```bash
kubectl exec -n opentelemetry deployment/otel-demo -- \
  env | grep '^OTEL'
```

---

# 26. Test the application

After startup and Ingress setup:

```bash
curl -s http://otel-demo.local/api
```

Expected response contains:

```json
{
  "status": "ok"
}
```

The actual response also contains the demo user and inventory data.

Health:

```bash
curl -s http://otel-demo.local/health
```

---

# 27. Successful distributed trace

Generate:

```bash
curl -s http://otel-demo.local/api
```

Then open:

```text
http://jaeger.local
```

Select:

```text
Service → otel-demo
```

You should see a trace similar to:

```text
otel-demo
└── GET /api
    └── process-api-request
        ├── user-service
        │   └── fetch-user
        │
        └── inventory-service
            └── check-inventory
```

The important point is that this is **one distributed trace**, not three unrelated traces.

---

# 28. Failure propagation demo

This is one of the most useful demonstrations in the lab.

Run:

```bash
curl -s "http://otel-demo.local/api?fail_inventory=true"
```

The expected high-level behavior is:

```text
otel-demo                  502
    │
    ├── user-service       200
    │
    └── inventory-service  500
```

In Jaeger, the failed trace identifies:

```text
inventory-service
    └── check-inventory
         ERROR
```

and the parent:

```text
otel-demo
    └── process-api-request
         ERROR
```

This demonstrates how distributed tracing helps locate the failing downstream dependency.

---

# 29. Application logs

The three Python services use the OpenTelemetry logging SDK.

The application log flow is:

```text
Python logging
     │
     ▼
OpenTelemetry logging SDK
     │
     │ OTLP/HTTP
     ▼
OTel Collector
     │
     │ otlp_http/victorialogs
     ▼
VictoriaLogs
```

The logs contain trace context such as:

```text
trace_id
span_id
```

That means a log entry can be connected back to the trace that produced it.

---

# 30. Verify application logs in VictoriaLogs

Open:

```text
http://grafana.local
```

Go to:

```text
Explore
```

Select:

```text
VictoriaLogs
```

Generate traffic first:

```bash
curl -s http://otel-demo.local/api >/dev/null
curl -s "http://otel-demo.local/api?fail_inventory=true" >/dev/null
```

Then search the logs.

Useful starting filters are:

```text
service.name:otel-demo
```

or search directly for:

```text
trace_id
```

Use the field browser in Grafana Explore to inspect the exact fields returned by your current VictoriaLogs plugin/data.

The lab's VictoriaLogs datasource is configured with the OpenTelemetry preset and the Jaeger datasource UID, so trace-aware navigation can be enabled when the detected trace ID field is present.

---

# 31. Logs ↔ traces workflow

The intended operational workflow is:

```text
1. Notice an error in a log
             │
             ▼
2. Read trace_id / span_id
             │
             ▼
3. Open the corresponding trace
             │
             ▼
4. See the complete distributed request
             │
             ▼
5. Identify the failing/slow service
             │
             ▼
6. Return to logs for detailed application context
```

This is the practical value of correlating the three signals.

---

# 32. Application metrics

The application also sends metrics through OTLP.

The path is:

```text
Application
    │
    │ OTLP
    ▼
OTel Collector
    │
    │ Prometheus exporter :8889
    ▼
Prometheus
    │
    ▼
Grafana
```

The verified metric family from the lab includes:

```text
app_requests_total
```

Check:

```promql
app_requests_total
```

or:

```promql
sum(rate(app_requests_total[5m]))
```

Do not assume that every possible latency/error metric exists. Inspect the actual metric families exposed by the current instrumentation/configuration.

---

# 33. Grafana application dashboard

The repository includes:

```text
dashboards/otel-demo-application-overview.json
```

Import it from:

```text
Grafana → Dashboards → Import
```

Select the existing Prometheus datasource.

Generate traffic:

```bash
for i in {1..20}; do
  curl -s http://otel-demo.local/api >/dev/null
done
```

Generate errors:

```bash
for i in {1..5}; do
  curl -s "http://otel-demo.local/api?fail_inventory=true" >/dev/null
done
```

Then inspect:

- request rate
- error rate
- request latency, where the metric is available
- endpoint traffic
- HTTP status distribution

---

# 34. NGINX Ingress

The following browser-facing hosts are configured:

```text
grafana.local
prometheus.local
elasticsearch.local
jaeger.local
otel-demo.local
```

VictoriaLogs and the Collector are internal-only.

Check:

```bash
kubectl get ingress -A
```

---

# 35. macOS + Minikube Docker networking

With Minikube using the Docker driver on macOS, the Minikube node IP is not the recommended browser entry point.

Check:

```bash
minikube ip
```

The reliable workflow is:

```text
Browser
   │
   ▼
127.0.0.1
   │
   ▼
NGINX Ingress
   │
   ▼
Minikube tunnel
```

Start the tunnel in a second terminal:

```bash
./scripts/tunnel.sh
```

Keep that terminal open.

---

# 36. Configure `/etc/hosts`

Run:

```bash
sudo ./scripts/hosts.sh
```

The script adds:

```text
127.0.0.1 grafana.local
127.0.0.1 prometheus.local
127.0.0.1 elasticsearch.local
127.0.0.1 jaeger.local
127.0.0.1 otel-demo.local
```

Verify:

```bash
grep -E 'grafana\.local|prometheus\.local|elasticsearch\.local|jaeger\.local|otel-demo\.local' /etc/hosts
```

---

# 37. Final browser URLs

With the tunnel running:

### Grafana

```text
http://grafana.local
```

### Prometheus

```text
http://prometheus.local
```

### Elasticsearch

```text
http://elasticsearch.local
```

### Jaeger

```text
http://jaeger.local
```

### Demo application

```text
http://otel-demo.local
```

---

# 38. Port-forwarding

Normal use does not require port-forwarding.

Port-forwarding is useful only for isolating an Ingress/networking problem.

Examples:

### Grafana

```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
```

### Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
```

### Jaeger

```bash
kubectl port-forward -n opentelemetry svc/jaeger 16686:16686
```

### VictoriaLogs

```bash
kubectl port-forward \
  -n logging \
  svc/victoria-logs-victoria-logs-single-server \
  9428:9428
```

Do not add these to the normal daily workflow.

---

# 39. Complete validation

Run:

```bash
./scripts/validate.sh
```

The validation script checks:

- Minikube
- Kubernetes node
- Elasticsearch
- Elasticsearch PVCs
- Prometheus
- Grafana
- VictoriaLogs
- Collector
- Collector ports
- Jaeger
- all three demo services
- NGINX Ingress
- exporter metrics
- Collector health
- application health

After validation, perform the end-to-end test:

```bash
curl -s http://otel-demo.local/api
```

```bash
curl -s "http://otel-demo.local/api?fail_inventory=true"
```

Then inspect:

```text
Jaeger      → distributed trace
Grafana     → application metrics
VictoriaLogs → application logs
```

---

# 40. Useful troubleshooting commands

## Kubernetes overview

```bash
kubectl get nodes
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
```

## Resource usage

```bash
kubectl top node
kubectl top pods -A
```

This is especially important because Elasticsearch, Prometheus, Grafana, VictoriaLogs, Collector, Jaeger and the demo services all share one local Minikube node.

## Collector

```bash
kubectl logs -n opentelemetry deployment/opentelemetry-collector --since=10m
```

## Jaeger

```bash
kubectl logs -n opentelemetry deployment/jaeger --tail=100
```

## VictoriaLogs

```bash
kubectl logs -n logging \
  -l app.kubernetes.io/instance=victoria-logs \
  --tail=100
```

## Demo application

```bash
kubectl logs -n opentelemetry deployment/otel-demo --tail=100
```

```bash
kubectl logs -n opentelemetry deployment/user-service --tail=100
```

```bash
kubectl logs -n opentelemetry deployment/inventory-service --tail=100
```

---

# 41. Common problems

## Grafana shows "No data"

First check Prometheus:

```promql
up
```

Then:

```promql
app_requests_total
```

Then:

```promql
sum(rate(app_requests_total[5m]))
```

Also check:

```bash
kubectl top pod -n monitoring -l app.kubernetes.io/name=grafana
```

If Grafana is close to 512Mi:

```bash
kubectl describe pod -n monitoring \
  -l app.kubernetes.io/name=grafana
```

---

## Grafana password does not work

Do not restart the tunnel.

The tunnel controls networking, not authentication.

Retrieve the Secret:

```bash
kubectl get secret grafana \
  -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

---

## Collector is running but 8889 is unreachable

Check:

```bash
kubectl get svc opentelemetry-collector -n opentelemetry
```

The Service must expose:

```text
8889/TCP
```

Remember:

```text
8888 = Collector internal telemetry metrics
8889 = Prometheus exporter for application metrics
```

---

## Traces appear in Collector logs but not Jaeger

Check:

```bash
kubectl logs \
  -n opentelemetry \
  deployment/opentelemetry-collector \
  --since=5m
```

The trace pipeline must export to:

```yaml
- debug
- otlp_grpc
```

and:

```yaml
otlp_grpc:
  endpoint: jaeger.opentelemetry.svc.cluster.local:4317
  tls:
    insecure: true
```

---

## Logs do not appear in VictoriaLogs

Check:

```bash
kubectl logs \
  -n opentelemetry \
  deployment/opentelemetry-collector \
  --since=5m
```

Check VictoriaLogs:

```bash
kubectl logs \
  -n logging \
  -l app.kubernetes.io/instance=victoria-logs \
  --tail=100
```

Check the Collector exporter endpoint:

```text
http://victoria-logs-victoria-logs-single-server.logging.svc.cluster.local:9428/insert/opentelemetry/v1/logs
```

Check VictoriaLogs:

```bash
kubectl get svc -n logging
```

---

## Browser cannot reach `.local` URLs

Check:

```bash
grep -E 'grafana\.local|prometheus\.local|elasticsearch\.local|jaeger\.local|otel-demo\.local' /etc/hosts
```

Then check:

```bash
minikube status
kubectl get pods -n ingress-nginx
kubectl get ingress -A
```

Start/restart the tunnel:

```bash
minikube tunnel --cleanup
./scripts/tunnel.sh
```

---

# 42. Day-to-day commands

### Start

```bash
./scripts/start.sh
```

### Stop without deleting data

```bash
./scripts/stop.sh
```

### Start the tunnel

```bash
./scripts/tunnel.sh
```

### Configure hosts

```bash
sudo ./scripts/hosts.sh
```

### Validate

```bash
./scripts/validate.sh
```

### Uninstall workloads but keep Minikube

```bash
./scripts/uninstall.sh
```

### Full clean-room reset

```bash
./scripts/reset.sh
```

---

# 43. Stop vs uninstall vs reset

## `stop.sh`

```bash
./scripts/stop.sh
```

Stops Minikube.

Kubernetes resources and local storage remain.

Use this when you simply want to pause the lab.

---

## `uninstall.sh`

```bash
./scripts/uninstall.sh
```

Removes the main workloads/namespaces but keeps the Minikube cluster.

Use this when you want to redeploy workloads without recreating the Minikube VM/container.

---

## `reset.sh`

```bash
./scripts/reset.sh
```

Deletes the entire Minikube profile and runs `start.sh` again.

This is the strongest reproducibility test.

It removes:

- Elasticsearch PVCs
- VictoriaLogs local storage
- all Kubernetes objects
- all transient Jaeger trace data
- all other lab state

---

# 44. Reproducibility test

A clean-room reproduction should be:

```bash
./scripts/reset.sh
```

Then:

```bash
./scripts/tunnel.sh
```

in a second terminal.

Then:

```bash
sudo ./scripts/hosts.sh
```

Then:

```bash
./scripts/validate.sh
```

Finally:

```bash
curl -s http://otel-demo.local/api
curl -s "http://otel-demo.local/api?fail_inventory=true"
```

Confirm:

```text
[ ] Elasticsearch is Running
[ ] Prometheus is Running
[ ] Grafana is Running
[ ] VictoriaLogs is Running
[ ] OTel Collector is Running
[ ] Jaeger is Running
[ ] user-service is Running
[ ] inventory-service is Running
[ ] otel-demo is Running

[ ] Prometheus exporter target is UP
[ ] Application metrics appear
[ ] Application logs appear in VictoriaLogs
[ ] Successful distributed trace appears in Jaeger
[ ] Failed distributed trace appears in Jaeger
[ ] Kubernetes metadata is visible
[ ] Grafana can access Prometheus
[ ] Grafana can access VictoriaLogs
[ ] Grafana has Jaeger datasource
[ ] Browser Ingress works without port-forwarding
```

---

# 45. Why this architecture is useful

The important lesson is that the Collector becomes the **control point for telemetry**.

Without a Collector:

```text
Application ──► Prometheus
Application ──► Jaeger
Application ──► Log backend
```

Every application becomes aware of backend-specific configuration.

With the Collector:

```text
                    ┌──► Prometheus
                    │
Application ──► Collector ──► Jaeger
                    │
                    └──► VictoriaLogs
```

The application only needs to know:

```text
OTLP endpoint
```

The Collector controls:

- routing
- batching
- memory protection
- Kubernetes metadata enrichment
- backend selection
- future sampling
- future filtering
- future transformations

---

# 46. Why VictoriaLogs is used for logs

The lab's logging goal is cost-conscious centralized application logging.

The final path is:

```text
Python application
      │
      │ OTLP logs
      ▼
OTel Collector
      │
      ▼
VictoriaLogs
      │
      ▼
Grafana
```

Elasticsearch is therefore no longer part of the application logging path.

It remains only as a monitored infrastructure component in this playground.

---

# 47. Why Jaeger is still separate in this lab

The lab intentionally does not introduce a second persistent trace database.

For learning:

```text
OTel Collector
      │
      ▼
Jaeger
      │
      ▼
In-memory trace store
```

This is enough to demonstrate:

- trace context propagation
- distributed traces
- service dependency
- latency
- error propagation
- trace IDs
- trace/span metadata

For production, the architecture would need a persistent trace backend and a deliberate retention/sampling policy.

That is a separate capacity/cost decision rather than a requirement for understanding OpenTelemetry.

---

# 48. Production direction after this lab

The lab stops here deliberately.

A production evolution could look like:

```text
                    ┌──► VictoriaMetrics
                    │
Application ─► OTel Collector
                    │
                    ├──► VictoriaLogs
                    │
                    └──► Trace backend
                              │
                              ▼
                           Jaeger
```

Before introducing a persistent trace backend, measure:

```text
requests/sec
spans/request
bytes/span
traces/day
retention
query workload
error/slow-trace percentage
```

Then apply sampling.

A practical policy is usually:

```text
100% of errors
100% of very slow/critical traces
small percentage of normal successful traffic
short trace retention
```

This keeps tracing useful without automatically creating another high-volume data platform.

---

# 49. Final learning path

The lab has now reached the intended end state.

```text
Stage 1
Kubernetes + Minikube
        │
        ▼
Stage 2
Elasticsearch + Exporter + Prometheus + Grafana
        │
        ▼
Stage 3
OpenTelemetry Collector
        │
        ├── metrics
        └── traces
        │
        ▼
Stage 4
Distributed tracing
        │
        ▼
Three-service application
        │
        ▼
Stage 5
Kubernetes metadata enrichment
        │
        ▼
Stage 6
Application logs
        │
        ▼
VictoriaLogs
        │
        ▼
Stage 7
Logs ↔ Metrics ↔ Traces
        │
        ▼
Stage 8
Production design considerations:
sampling + retention + persistent trace storage
```

---

# 50. Final architecture summary

```text
                                      macOS
                                        │
                               /etc/hosts + tunnel
                                        │
                                        ▼
                                 NGINX Ingress
                                        │
               ┌────────────────────────┼────────────────────────┐
               │                        │                        │
               ▼                        ▼                        ▼
           Grafana                  Prometheus                 Jaeger
               │                        ▲                        ▲
               │                        │                        │
               │                 application metrics            │
               │                        │                        │
               │                        │                        │
               │                  OTel Collector ────────────────┘
               │                    ▲       ▲
               │                    │       │
               │                 logs      traces
               │                    │       │
               │                    ▼       │
               │              VictoriaLogs  │
               │                    ▲       │
               │                    │       │
               └────────────────────┼───────┘
                                    │
                           OpenTelemetry SDKs
                                    │
                         ┌──────────┼──────────┐
                         │          │          │
                         ▼          ▼          ▼
                    otel-demo  user-service  inventory-service
                         │
                         └──── distributed trace context ────┐
                                                              │
                                                              ▼
                                                    Complete request trace
```

Infrastructure monitoring remains:

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

The result is a compact local playground that demonstrates the core Platform Engineering observability model:

```text
                    Logs
                     │
                     ▼
                 VictoriaLogs
                     ▲
                     │
Metrics ──► Prometheus ◄── OTel Collector ──► Traces
                     │                         │
                     ▼                         ▼
                  Grafana                    Jaeger
```

**Lab conclusion:** application telemetry is now centralized through OpenTelemetry, logs are stored in VictoriaLogs, metrics in Prometheus, traces are explored in Jaeger, Kubernetes metadata is attached by the Collector, and Grafana provides the common metrics/logs exploration experience without requiring port-forwarding for normal browser use.
