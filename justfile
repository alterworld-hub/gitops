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
    for d in components/* nodes/* nodes/*/*/; do
      [ -f "$d/kustomization.yaml" ] || continue
      echo "== $d"
      kubectl kustomize "$d" | {{kubeconform}}
    done

# Regenerate Flux components for a node at the installed flux CLI version
flux-components node:
    flux install --export > nodes/{{node}}/flux-system/gotk-components.yaml

# Declare a Postgres role + database for a service; credentials land in Secret `postgres` of namespace <name>
db-add node name:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{name}}" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "name: lowercase kebab-case"; exit 1; }
    dir=nodes/{{node}}/data/databases; file=$dir/{{name}}.yaml
    [ -e "$file" ] && { echo "$file exists"; exit 1; }
    NODE={{node}} NAME={{name}} PG=$(tr - _ <<<"{{name}}") envsubst '${NODE} ${NAME} ${PG}' < bootstrap/database.yaml.tpl > "$file"
    (cd $dir && kustomize_files=$(ls *.yaml | grep -v '^kustomization.yaml$' | sed 's/^/  - /') && printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n%s\n' "$kustomize_files" > kustomization.yaml)
    echo "created $file; commit it, the service reads /etc/postgres/{host,port,dbname,username,password,uri}"

# psql as postgres inside the node's cluster (current kube context)
psql db="postgres":
    kubectl exec -it -n postgres main-1 -c postgres -- psql {{db}}

# Forward the node's Postgres to localhost:5432 for local development
pg-forward:
    kubectl port-forward -n postgres svc/main-rw 5432:5432
