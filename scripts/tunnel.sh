#!/usr/bin/env bash
set -euo pipefail

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}"

echo "Starting Minikube tunnel for profile: $MINIKUBE_PROFILE"
echo "Keep this terminal open while using the Ingress URLs."
echo
echo "Expected host-side address for Docker Desktop/macOS:"
echo "  127.0.0.1"
echo
echo "If an old tunnel left stale routes, stop this process and run:"
echo "  minikube tunnel --cleanup -p $MINIKUBE_PROFILE"
echo
exec minikube tunnel -p "$MINIKUBE_PROFILE"
