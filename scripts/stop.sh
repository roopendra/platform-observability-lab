#!/usr/bin/env bash
set -euo pipefail

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}"

if minikube status -p "$MINIKUBE_PROFILE" >/dev/null 2>&1; then
  minikube stop -p "$MINIKUBE_PROFILE"
  echo "Minikube stopped. Data and Kubernetes resources are retained."
else
  echo "Minikube profile '$MINIKUBE_PROFILE' does not exist or is already stopped."
fi

echo "Start again with: ./scripts/start.sh"
