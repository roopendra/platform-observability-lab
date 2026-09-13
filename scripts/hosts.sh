#!/usr/bin/env bash
set -euo pipefail

HOSTS=(
  "grafana.local"
  "prometheus.local"
  "elasticsearch.local"
  "jaeger.local"
  "otel-demo.local"
)
HOST_IP="${HOST_IP:-127.0.0.1}"

for host in "${HOSTS[@]}"; do
  if grep -Eq "^[[:space:]]*${HOST_IP}[[:space:]]+${host}([[:space:]]|$)" /etc/hosts; then
    echo "Already present: ${HOST_IP} ${host}"
  elif grep -Eq "[[:space:]]${host}([[:space:]]|$)" /etc/hosts; then
    echo "WARNING: ${host} already exists in /etc/hosts with a different IP."
    echo "Review it manually before continuing."
  else
    echo "Adding: ${HOST_IP} ${host}"
    printf '%s %s\n' "$HOST_IP" "$host" >> /etc/hosts
  fi
done

echo
echo "Current entries:"
grep -E '(^|[[:space:]])(grafana|prometheus|elasticsearch|jaeger|otel-demo)\.local([[:space:]]|$)' /etc/hosts || true
