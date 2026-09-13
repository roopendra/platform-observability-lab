#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}"

echo "WARNING: this will DELETE the Minikube cluster and all local lab data, including Elasticsearch PVCs."
echo "VictoriaLogs is configured without a persistent volume in this lab, so its logs are also lost."
read -r -p "Type DELETE to continue: " answer
[[ "$answer" == "DELETE" ]] || { echo "Cancelled."; exit 0; }

minikube tunnel --cleanup >/dev/null 2>&1 || true
minikube delete -p "$MINIKUBE_PROFILE"

exec ./scripts/start.sh
