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
db-add node name: (_add "database" "databases" node name)

# Declare a RabbitMQ user + permissions (prefix <name>.) for a service; credentials land in Secret `rabbitmq` of namespace <name>
mq-add node name: (_add "rabbitmq-user" "rabbitmq-users" node name)

_add tpl dir node name:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{name}}" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "name: lowercase kebab-case"; exit 1; }
    dir=nodes/{{node}}/data/{{dir}}; file=$dir/{{name}}.yaml
    [ -e "$file" ] && { echo "$file exists"; exit 1; }
    NODE={{node}} NAME={{name}} PG=$(tr - _ <<<"{{name}}") envsubst '${NODE} ${NAME} ${PG}' < bootstrap/{{tpl}}.yaml.tpl > "$file"
    (cd $dir && printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n%s\n' "$(ls *.yaml | grep -vx kustomization.yaml | sed 's/^/  - /')" > kustomization.yaml)
    echo "created $file; commit it via PR"

# psql as postgres inside the node's cluster (current kube context)
psql db="postgres":
    kubectl exec -it -n postgres main-1 -c postgres -- psql {{db}}

# Forward the node's Postgres to localhost:5432 for local development
pg-forward:
    kubectl port-forward -n postgres svc/main-rw 5432:5432

# RabbitMQ admin login for the management UI (prints the node's default user)
mq-admin:
    @kubectl get secret -n rabbitmq main-default-user -o go-template='user: {{"{{"}}.data.username | base64decode{{"}}"}}{{"{{"}}"\n"{{"}}"}}password: {{"{{"}}.data.password | base64decode{{"}}"}}{{"{{"}}"\n"{{"}}"}}'

# Re-vendor RabbitMQ operator release manifests
vendor-rabbitmq cluster topology:
    #!/usr/bin/env bash
    set -euo pipefail
    d=components/rabbitmq-operators
    for f in "cluster-operator.yaml https://github.com/rabbitmq/cluster-operator/releases/download/v{{cluster}}/cluster-operator-ghcr-io.yml" \
             "messaging-topology-operator.yaml https://github.com/rabbitmq/messaging-topology-operator/releases/download/v{{topology}}/messaging-topology-operator-with-certmanager.yaml"; do
      set -- $f
      body=$(curl -fsSL "$2")
      # Both releases declare Namespace rabbitmq-system; keep the cluster operator's.
      [ "$1" = messaging-topology-operator.yaml ] && body=$(python3 -c 'import re,sys; print("---".join(x for x in re.split(r"(?m)^---\s*$", sys.stdin.read()) if not re.search(r"(?m)^kind: Namespace$", x)), end="")' <<<"$body")
      { echo "# Vendored: $2"; echo "# Update: just vendor-rabbitmq <cluster-operator-version> <topology-operator-version>"; echo "$body"; } > "$d/$1"
    done

# Forward the node's RabbitMQ (AMQP) to localhost:5672 for local development
mq-forward:
    kubectl port-forward -n rabbitmq svc/main 5672:5672
