kubeconform := "docker run --rm -i ghcr.io/yannh/kubeconform:v0.8.0 -strict -summary -ignore-missing-schemas -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'"

default:
    @just --list

# Create local k3d node (no bundled Traefik; LB on :8080) and bootstrap Flux
local-up:
    k3d cluster create local --k3s-arg "--disable=traefik@server:0" -p "8080:80@loadbalancer" --wait
    bootstrap/install-node.sh local

local-down:
    k3d cluster delete local

# Render every kustomization and validate against k8s + CRD schemas
validate:
    #!/usr/bin/env bash
    set -euo pipefail
    for d in platform apps/* nodes/* nodes/*/apps; do
      echo "== $d"
      kubectl kustomize "$d" | {{kubeconform}}
    done

# Regenerate Flux components for a node at the installed flux CLI version
flux-components node:
    flux install --export > nodes/{{node}}/flux-system/gotk-components.yaml
