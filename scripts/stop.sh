#!/usr/bin/env bash
set -euo pipefail

K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-lab-cluster}"

if k3d cluster list -o json | grep -Eq '"name"[[:space:]]*:[[:space:]]*"'"$K3D_CLUSTER_NAME"'"'; then
  k3d cluster stop "$K3D_CLUSTER_NAME"
  echo "k3d cluster stopped. Data and Kubernetes resources are retained."
else
  echo "k3d cluster '$K3D_CLUSTER_NAME' does not exist."
fi

echo "Start again with: ./scripts/start.sh"
