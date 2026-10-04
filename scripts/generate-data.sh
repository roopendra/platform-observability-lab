#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${OTEL_DEMO_URL:-http://otel-demo.local:8080}"
SUCCESS_COUNT="${SUCCESS_COUNT:-20}"
FAILURE_COUNT="${FAILURE_COUNT:-5}"
ERROR_COUNT="${ERROR_COUNT:-5}"

echo "Generating telemetry against: $BASE_URL"

echo "Generating ${SUCCESS_COUNT} successful distributed requests..."
for i in $(seq 1 "$SUCCESS_COUNT"); do
  curl -fsS "$BASE_URL/api" >/dev/null
done

echo "Generating ${FAILURE_COUNT} failed distributed requests..."
for i in $(seq 1 "$FAILURE_COUNT"); do
  curl -sS "$BASE_URL/api?fail_inventory=true" >/dev/null || true
done

echo "Generating ${ERROR_COUNT} direct application errors..."
for i in $(seq 1 "$ERROR_COUNT"); do
  curl -sS "$BASE_URL/error" >/dev/null || true
done

echo
echo "Telemetry generated."
echo "Grafana:  http://grafana.local:8080"
echo "Jaeger:   http://jaeger.local:8080"
echo "Demo app: $BASE_URL"
