# gitops

Desired state of every node. Flux on each node pulls `nodes/<node-path>` (read-only). CI never touches nodes.

Conventions: [alterworld-hub/.github](https://github.com/alterworld-hub/.github/blob/main/CONVENTIONS.md).

## Layout
| Path | Holds |
|---|---|
| `features.toml` | Node features (Cargo-style): component → layer, features, codenames |
| `nodes/<path>/node.toml` | Features enabled on the node |
| `components/<name>/` | Every deployable component, same shape: namespace, source, HelmRelease. Version placeholder only |
| `nodes/<path>/<layer>/` | Generated kustomization (`just features`) + `<name>.version.yaml` per component + node-local dirs |
| `nodes/<path>/<layer>.yaml` | Flux Kustomization applying that layer with node variables (`NODE_DOMAIN`, `NODE_PATH`) |
| `nodes/<path>/flux-system/` | Flux components (pinned) + sync of this node |
| `bootstrap/` | One-time node install; templates used by `just` |

Layers per node:
- `infrastructure`: CRD/controller providers (Helm): traefik, cert-manager, external-secrets, cloudnative-pg.
- `operators`: operators shipped as plain manifests needing layer-1 CRDs: RabbitMQ cluster + topology operators (vendored, `just vendor-rabbitmq`).
- `data`: data services: Postgres cluster `main`, RabbitMQ cluster `main`, per-service databases and users. Ready only when they are (CEL health checks).
- `apps`: everything else. `dependsOn: infrastructure` only if the app uses layer-1 CRDs.

## Node features
Nodes run the same code and differ only by enabled features, declared like Cargo features in `features.toml`:
```toml
[features]
core = ["dep:traefik", "dep:cert-manager", "dep:external-secrets"] # on every node
postgres = ["dep:cloudnative-pg", "dep:postgres"]
lados = ["postgres", "rabbitmq", "web"]                             # codename = set of features
```
A node picks features in `nodes/<path>/node.toml` (`features = ["lados"]`). `just features` renders the node's layer kustomizations; never edit them by hand. CI (`just features --check`) fails on unknown names, cycles, missing or stale version files, node-local dirs whose component is off (`data/databases` needs Postgres), and out-of-date files.

Turning a feature off takes two PRs, because Flux prunes layers in no fixed order and an operator removed before its objects leaves their finalizers stuck:
1. In `node.toml` move it from `features` to `teardown = ["<feature>"]`, delete what the check names, `just features`. Its objects go; its providers (`infrastructure`/`operators` components) stay and finalize them.
2. Remove it from `teardown`, `just features`. The providers go.

CI (`--base origin/main`) rejects a provider removed while its feature was still on.

New component: `components/<name>/`, add it to `[components]` with its layer and to a feature; per-node chart version in `nodes/<path>/<layer>/<name>.version.yaml`.

Version files: service charts are bumped by the CI bot (`gitops-bump`); third-party charts by Renovate (`alterworld-hub/.github`), which needs a hint above the tag (prefer a datasource with release dates, e.g. the chart's Helm repo, so minimumReleaseAge works):
```yaml
    # renovate: datasource=helm depName=traefik registryUrl=https://traefik.github.io/charts
    tag: 41.7.1
```

## Postgres for a service
One CloudNativePG cluster per node (`main`, namespace `postgres`). Per service: role + database (snake_case of the service name), password generated on the node by ESO (`CreatedOnce`), never in git.

1. `just db-add <node> <service>` → `nodes/<node>/data/databases/<service>.yaml`; commit via PR.
2. Secret `postgres` appears in namespace `<service>` (when it exists): `host`, `port`, `dbname`, `username`, `password`, `uri`.
3. The service mounts it as files and reads them at start:
   ```yaml
   volumeMounts: [{name: postgres, mountPath: /etc/postgres, readOnly: true}]
   volumes: [{name: postgres, secret: {secretName: postgres}}]
   ```

Local development against the node: `just pg-forward` (localhost:5432) and the credentials from that Secret. Admin shell: `just psql [db]`.

## RabbitMQ for a service
One RabbitMQ cluster per node (`main`, namespace `rabbitmq`), vhost `alterworld`. Per service: user with username and password generated on the node by the topology operator (`<service>-user-credentials`), copied into the service namespace by ESO.
Permissions: configure/write `<service>.*`, read own + `*.events` (publish to your exchanges, subscribe to anyone's `*.events`).

1. `just mq-add <node> <service>` → `nodes/<node>/data/rabbitmq-users/<service>.yaml`; commit via PR.
2. Secret `rabbitmq` appears in namespace `<service>`: `host`, `port`, `vhost`, `username`, `password`, `uri`; mount as files (`/etc/rabbitmq`).

Management UI: http://rabbitmq.local.alterworld-hub.localhost:8080 (login: `just mq-admin`). Local development: `just mq-forward` (localhost:5672).

Known limits (Postgres, RabbitMQ): one instance, no backups yet; any namespace may reference store `postgres` ([gitops#52](https://github.com/alterworld-hub/gitops/issues/52)).

## Cluster UI
Nothing runs on the node for this: clients talk to its Kubernetes API with your kube context.
- [Headlamp](https://headlamp.dev) desktop (`brew install --cask headlamp`); Flux plugin from its plugin catalog.
- [k9s](https://k9s.io) in the terminal (`brew install k9s`, `k9s --context k3d-local`).

## Commands
| | |
|---|---|
| `just local-up` | k3d node `local` + Flux; Traefik dashboard: http://traefik.local.alterworld-hub.localhost:8080/dashboard/ |
| `just local-down` | Delete it |
| `just features [--check]` | Render node layers from features (check: CI mode) |
| `just db-add <node> <service>` | Declare a Postgres role + database for a service |
| `just psql [db]` / `just pg-forward` | Admin psql in the node cluster / forward Postgres to localhost:5432 |
| `just mq-add <node> <service>` | Declare a RabbitMQ user + permissions for a service |
| `just mq-admin` / `just mq-forward` | Management UI login / forward AMQP to localhost:5672 |
| `just vendor-rabbitmq <cluster> <topology>` | Re-vendor RabbitMQ operator manifests |
| `just validate` | Render and schema-check all kustomizations (same as CI) |
| `just flux-components <node>` | Re-pin Flux components to the installed CLI version |

## Rules
- Change state only via PR. Merge = deploy.
- Pin every version: chart tags, images by digest.
- Secrets only SOPS-encrypted.
