#!/usr/bin/env bash
set -euo pipefail

fail=0

check() {
  if "$@"; then
    echo "OK: $*"
  else
    echo "FAIL: $*" >&2
    fail=1
  fi
}

run_curl_check() {
  local namespace="$1"
  local pod="$2"
  local url="$3"
  local pattern="${4:-}"

  kubectl delete pod "$pod" -n "$namespace" --ignore-not-found=true >/dev/null 2>&1 || true

  kubectl run "$pod" -n "$namespace" \
    --image=curlimages/curl:8.10.1 \
    --restart=Never \
    --command -- \
    sh -c "curl -fsS --max-time 20 '$url'${pattern:+ | grep -m1 '$pattern'}" \
    >/dev/null

  local phase=""
  for _ in {1..30}; do
    phase="$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "$phase" in
      Succeeded|Failed) break ;;
    esac
    sleep 1
  done

  if [[ "$phase" == "Succeeded" ]]; then
    kubectl logs "$pod" -n "$namespace" --tail=3 || true
    kubectl delete pod "$pod" -n "$namespace" --ignore-not-found=true >/dev/null 2>&1 || true
    return 0
  fi

  echo "Pod $pod did not complete successfully (phase: ${phase:-unknown})." >&2
  kubectl logs "$pod" -n "$namespace" --tail=20 >&2 || true
  kubectl describe pod "$pod" -n "$namespace" >&2 || true
  kubectl delete pod "$pod" -n "$namespace" --ignore-not-found=true >/dev/null 2>&1 || true
  return 1
}

echo "=== Minikube ==="
check minikube status -p "${MINIKUBE_PROFILE:-minikube}"
check kubectl get nodes

echo
echo "=== Elasticsearch ==="
kubectl get pods -n elastic
check kubectl get pod es-master-0 -n elastic
check kubectl get pod es-data-0 -n elastic
kubectl get svc -n elastic
kubectl get pvc -n elastic

echo
echo "=== Monitoring ==="
kubectl get pods -n monitoring
kubectl get svc -n monitoring
check kubectl get deployment/prometheus-server -n monitoring
check kubectl get deployment/grafana -n monitoring

echo
echo "=== VictoriaLogs ==="
kubectl get pods -n logging
kubectl get svc -n logging
check kubectl get pod -l app.kubernetes.io/instance=victoria-logs -n logging
if run_curl_check logging "victorialogs-check-$$" \
    "http://victoria-logs-victoria-logs-single-server:9428/metrics" \
    '^vl_'; then
  echo "OK: VictoriaLogs /metrics is reachable"
else
  echo "FAIL: VictoriaLogs /metrics check failed" >&2
  fail=1
fi

echo
echo "=== OpenTelemetry ==="
kubectl get pods -n opentelemetry
kubectl get svc -n opentelemetry
check kubectl get deployment/opentelemetry-collector -n opentelemetry
check kubectl get deployment/jaeger -n opentelemetry
check kubectl get deployment/user-service -n opentelemetry
check kubectl get deployment/inventory-service -n opentelemetry
check kubectl get deployment/otel-demo -n opentelemetry

if kubectl get svc opentelemetry-collector -n opentelemetry >/dev/null 2>&1; then
  for port in 13133 4317 4318 8889; do
    if kubectl get svc opentelemetry-collector -n opentelemetry -o jsonpath='{.spec.ports[*].port}' \
      | tr ' ' '\n' | grep -qx "$port"; then
      echo "OK: Collector Service exposes $port/TCP"
    else
      echo "FAIL: Collector Service is missing $port/TCP" >&2
      fail=1
    fi
  done
fi

echo
echo "=== Ingress ==="
kubectl get ingress -A
kubectl get pods -n ingress-nginx
for host in grafana.local prometheus.local elasticsearch.local jaeger.local otel-demo.local; do
  if kubectl get ingress -A -o jsonpath='{range .items[*].spec.rules[*]}{.host}{"\n"}{end}' \
      | grep -qx "$host"; then
    echo "OK: Ingress host $host exists"
  else
    echo "FAIL: Ingress host $host is missing" >&2
    fail=1
  fi
done

echo
echo "=== Helm ==="
helm list -n monitoring
helm list -n logging
helm list -n opentelemetry

echo
echo "=== Exporter metrics smoke test ==="
if run_curl_check monitoring "exporter-check-$$" \
    "http://elasticsearch-exporter-prometheus-elasticsearch-exporter:9108/metrics" \
    '^elasticsearch_'; then
  echo "OK: exporter /metrics is reachable"
else
  echo "FAIL: exporter /metrics check failed" >&2
  fail=1
fi

echo
echo "=== Collector health smoke test ==="
if run_curl_check opentelemetry "collector-health-check-$$" \
    "http://opentelemetry-collector:13133/"; then
  echo "OK: Collector health endpoint is reachable"
else
  echo "FAIL: Collector health endpoint check failed" >&2
  fail=1
fi

echo
echo "=== OTel demo health smoke test ==="
if run_curl_check opentelemetry "otel-demo-health-check-$$" \
    "http://otel-demo:8080/health"; then
  echo "OK: otel-demo /health is reachable"
else
  echo "FAIL: otel-demo /health check failed" >&2
  fail=1
fi

echo
echo "=== Distributed service health smoke tests ==="
if run_curl_check opentelemetry "user-health-check-$$" \
    "http://user-service:8081/health"; then
  echo "OK: user-service /health is reachable"
else
  echo "FAIL: user-service /health check failed" >&2
  fail=1
fi

if run_curl_check opentelemetry "inventory-health-check-$$" \
    "http://inventory-service:8082/health"; then
  echo "OK: inventory-service /health is reachable"
else
  echo "FAIL: inventory-service /health check failed" >&2
  fail=1
fi

echo
echo "=== Jaeger service check ==="
check kubectl get svc jaeger -n opentelemetry
if run_curl_check opentelemetry "jaeger-ui-check-$$" \
    "http://jaeger:16686/"; then
  echo "OK: Jaeger UI is reachable"
else
  echo "FAIL: Jaeger UI check failed" >&2
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  echo
  echo "Validation completed successfully."
  echo
  echo "Next E2E checks:"
  echo "  curl -s http://otel-demo.local/api"
  echo "  curl -s 'http://otel-demo.local/api?fail_inventory=true'"
  echo "  Then inspect the trace in Jaeger and logs in Grafana → Explore → VictoriaLogs."
else
  echo
  echo "Validation found one or more failures. Use the troubleshooting section in README.md."
  exit 1
fi
