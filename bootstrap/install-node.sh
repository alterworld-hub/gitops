#!/usr/bin/env bash
# Install Flux on the current kubectl context and point it at nodes/<node>.
# Usage: bootstrap/install-node.sh <node-path>   e.g. local, root/org-a/site-1
set -euo pipefail
node="${1:?node path required}"
dir="nodes/${node}/flux-system"
[[ -d "$dir" ]] || { echo "no such node: $dir" >&2; exit 1; }

kubectl apply --server-side -f "$dir/gotk-components.yaml"
kubectl wait --for=condition=established --timeout=2m crd --all
kubectl -n flux-system rollout status deploy --timeout=3m
kubectl apply -f "$dir/gotk-sync.yaml"
