#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-lab-cluster}"

echo "WARNING: this will DELETE the k3d cluster '$K3D_CLUSTER_NAME' and all local lab data, including Elasticsearch PVCs."
echo "VictoriaLogs is configured without a persistent volume in this lab, so its logs are also lost."
read -r -p "Type DELETE to continue: " answer
[[ "$answer" == "DELETE" ]] || { echo "Cancelled."; exit 0; }

k3d cluster delete "$K3D_CLUSTER_NAME"
k3d cluster create "$K3D_CLUSTER_NAME"
kubectl config use-context "k3d-$K3D_CLUSTER_NAME" >/dev/null

exec ./scripts/start.sh
