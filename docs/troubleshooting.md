# Troubleshooting Quick Reference

## Start here

```bash
docker info
k3d cluster list
kubectl get nodes
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
kubectl top node
kubectl top pods -A
```

For a full check:

```bash
./scripts/validate.sh
```

If `docker info` cannot connect on macOS, open OrbStack and retry. Confirm the `docker` CLI is available and points to OrbStack's Docker-compatible engine before running `start.sh`.

---

## Elasticsearch

```bash
kubectl get pods -n elastic
kubectl describe pod es-master-0 -n elastic
kubectl describe pod es-data-0 -n elastic
kubectl logs -n elastic es-master-0
kubectl logs -n elastic es-data-0
```

Test the HTTP API:

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

## Elasticsearch exporter

```bash
kubectl get pods -n monitoring
kubectl logs -n monitoring -l app.kubernetes.io/instance=elasticsearch-exporter
```

Test:

```bash
kubectl run curl-exporter \
  -n monitoring \
  --image=curlimages/curl:8.10.1 \
  --restart=Never \
  --rm -it \
  -- \
  curl -s http://elasticsearch-exporter-prometheus-elasticsearch-exporter:9108/metrics
```

---

## Prometheus

Check scrape configuration:

```bash
kubectl get configmap prometheus-server -n monitoring -o yaml \
  | grep -A12 -B2 elasticsearch-exporter
```

Check the Collector target too:

```bash
kubectl get configmap prometheus-server -n monitoring -o yaml \
  | grep -A12 -B2 otel-collector
```

Expected targets:

```text
elasticsearch-exporter:9108
opentelemetry-collector:8889
```

In Prometheus:

```promql
up{job="elasticsearch-exporter"}
```

```promql
up{job="otel-collector"}
```

---

## Grafana

Check:

```bash
kubectl get pods -n monitoring
kubectl logs -n monitoring -l app.kubernetes.io/instance=grafana
```

The final configuration provides:

```text
Prometheus
Jaeger
VictoriaLogs
```

If the VictoriaLogs datasource is missing, check the Grafana plugin:

```bash
kubectl exec -n monitoring deployment/grafana -- \
  grafana cli plugins ls
```

The expected plugin is:

```text
victoriametrics-logs-datasource
```

Retrieve the password:

```bash
kubectl get secret grafana \
  -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

---

## VictoriaLogs

Check:

```bash
kubectl get pods -n logging
kubectl get svc -n logging
helm status victoria-logs -n logging
```

Check logs:

```bash
kubectl logs -n logging \
  -l app.kubernetes.io/instance=victoria-logs \
  --tail=100
```

Check the HTTP endpoint:

```bash
kubectl run vl-check \
  -n logging \
  --image=curlimages/curl:8.10.1 \
  --restart=Never \
  --rm -it \
  -- \
  curl -fsS http://victoria-logs-victoria-logs-single-server:9428/metrics
```

The OTLP logs endpoint is:

```text
http://victoria-logs-victoria-logs-single-server.logging.svc.cluster.local:9428/insert/opentelemetry/v1/logs
```

If logs are missing:

1. Generate a fresh request.
2. Check Collector logs.
3. Check VictoriaLogs logs.
4. Check the Grafana VictoriaLogs datasource.

Generate traffic:

```bash
curl -s http://otel-demo.local:8080/api >/dev/null
curl -s "http://otel-demo.local:8080/api?fail_inventory=true" >/dev/null
```

---

## OpenTelemetry Collector

Check:

```bash
kubectl get pods -n opentelemetry
kubectl get svc opentelemetry-collector -n opentelemetry
kubectl logs -n opentelemetry deployment/opentelemetry-collector --since=10m
```

Expected Service ports:

```text
13133  health
4317   OTLP/gRPC
4318   OTLP/HTTP
8889   Prometheus exporter
```

Remember:

```text
8888 = Collector internal telemetry
8889 = application metrics exported for Prometheus
```

---

## Collector receives traces but Jaeger does not show them

Check:

```bash
kubectl logs \
  -n opentelemetry \
  deployment/opentelemetry-collector \
  --since=5m
```

The traces pipeline must export to:

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

## Jaeger

Check:

```bash
kubectl get pods -n opentelemetry
kubectl get svc jaeger -n opentelemetry
kubectl logs -n opentelemetry deployment/jaeger --tail=100
```

Jaeger UI:

```text
http://jaeger.local:8080
```

Remember that the lab uses in-memory trace storage. A Jaeger restart loses existing traces.

---

## Distributed demo application

Check:

```bash
kubectl get pods -n opentelemetry
kubectl get svc -n opentelemetry
```

Expected deployments:

```text
otel-demo
user-service
inventory-service
opentelemetry-collector
jaeger
```

Health checks:

```bash
curl -s http://otel-demo.local:8080/health
```

```bash
curl -s http://otel-demo.local:8080/api
```

Failure test:

```bash
curl -s "http://otel-demo.local:8080/api?fail_inventory=true"
```

Expected failure flow:

```text
otel-demo                  502
    └── inventory-service  500
```

If only the parent span is visible, inspect the child service deployments and Collector trace pipeline.

---

## Application logs have no trace ID

Check the application and Collector logs:

```bash
kubectl logs -n opentelemetry deployment/otel-demo --tail=100
kubectl logs -n opentelemetry deployment/opentelemetry-collector --since=5m
```

Generate a new request:

```bash
curl -s http://otel-demo.local:8080/api >/dev/null
```

The Python services use OpenTelemetry logging and trace context.

The log path is:

```text
application
  ↓ OTLP
Collector
  ↓ OTLP HTTP
VictoriaLogs
```

---

## Browser access fails

Check `/etc/hosts`:

```bash
grep -E 'grafana\.local|prometheus\.local|elasticsearch\.local|jaeger\.local|otel-demo\.local' /etc/hosts
```

Expected address:

```text
127.0.0.1
```

Check Ingress:

```bash
kubectl get ingress -A
kubectl get pods -n ingress-nginx
```

Start the Ingress port-forward (keep it running in its terminal):

```bash
./scripts/tunnel.sh
```

---

## Port-forward isolation test

If Ingress is broken, test services directly.

```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
```

```bash
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
```

```bash
kubectl port-forward -n opentelemetry svc/jaeger 16686:16686
```

```bash
kubectl port-forward \
  -n logging \
  svc/victoria-logs-victoria-logs-single-server \
  9428:9428
```

If these work while `.local:8080` URLs do not, the workloads are likely healthy and the problem is in the Ingress or port-forward path.

---

## Clean-room recovery

If the lab gets into an unknown state:

```bash
./scripts/reset.sh
```

This deletes the k3d cluster and all its data, recreates it, and reinstalls the complete environment.
