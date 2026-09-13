# OTel Demo 1.2 — Distributed Trace Demo

This version expands the original single-service Flask demo into a small
three-service request flow:

```text
Browser
  |
  v
otel-demo: GET /api
  |
  +----> user-service: GET /users/123
  |
  +----> inventory-service: GET /inventory/item-001
```

All services send telemetry to the OpenTelemetry Collector.

## Expected trace

A successful request should produce a trace similar to:

```text
otel-demo: GET /api
  |
  +-- process-api-request
       |
       +-- HTTP GET user-service
       |     |
       |     +-- user-service: GET /users/123
       |            |
       |            +-- fetch-user
       |
       +-- HTTP GET inventory-service
             |
             +-- inventory-service: GET /inventory/item-001
                    |
                    +-- check-inventory
```

The exact span names and hierarchy can vary slightly with instrumentation versions.

## Build inside Minikube

From this directory:

```bash
eval "$(minikube docker-env -p minikube)"

docker build -t otel-demo:1.2 .
docker build -t otel-user-service:1.0 ./user-service
docker build -t otel-inventory-service:1.0 ./inventory-service
```

## Deploy

```bash
kubectl apply -f user-service/deployment.yaml
kubectl apply -f inventory-service/deployment.yaml
kubectl apply -f deployment.yaml
kubectl apply -f ingress.yaml
```

Wait for the workloads:

```bash
kubectl rollout status deployment/user-service -n opentelemetry
kubectl rollout status deployment/inventory-service -n opentelemetry
kubectl rollout status deployment/otel-demo -n opentelemetry
```

## Verify

```bash
curl http://otel-demo.local/health
curl http://otel-demo.local/api
```

Generate several requests:

```bash
for i in {1..5}; do
  curl -s http://otel-demo.local/api
  echo
done
```

Then open Jaeger and search for:

```text
otel-demo
```

You should now see multiple services and multiple spans.

## Demonstrate an error

```bash
curl -s "http://otel-demo.local/api?fail_inventory=true"
```

The root service should return HTTP 502 because the inventory service deliberately
returns HTTP 500.

In Jaeger, the trace should show the inventory branch as the failing part.

## Demonstrate latency

The inventory service intentionally waits 100ms. This makes the downstream
latency visible in Jaeger without making the demo excessively slow.

## Important

The application logs are also sent using OTLP to the OpenTelemetry Collector.
The Collector currently routes logs to VictoriaLogs.

The request trace context is propagated from `otel-demo` to the downstream services
by the OpenTelemetry Requests instrumentation. This is the key behavior we want
to demonstrate in the distributed tracing stage.
