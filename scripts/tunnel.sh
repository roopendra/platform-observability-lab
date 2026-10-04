#!/usr/bin/env bash
set -euo pipefail

echo "Forwarding local port 8080 to the NGINX Ingress Controller."
echo "Keep this terminal open and use URLs with :8080, such as http://grafana.local:8080."
echo "Press Ctrl-C to stop forwarding."
exec kubectl port-forward --address 127.0.0.1 -n ingress-nginx \
  svc/ingress-nginx-controller 8080:80
