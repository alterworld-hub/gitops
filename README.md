# gitops

Desired state of every node. Flux on each node pulls `nodes/<node-path>` (read-only). CI never touches nodes.

Conventions: [alterworld-hub/.github](https://github.com/alterworld-hub/.github/blob/main/CONVENTIONS.md).

## Layout
| Path | Holds |
|---|---|
| `features.yaml` | Platform components, feature-toggled components, features and codenames |
| `nodes/<path>/node.yaml` | Features enabled on the node |
| `components/<name>/` | Every deployable component, same shape: namespace, source, HelmRelease. Version placeholder only |
| `nodes/<path>/<layer>/` | Generated kustomization and `data/services/<svc>.yaml` (`just features`) + `<name>.version.yaml` per component |
| `nodes/<path>/<layer>.yaml` | Flux Kustomization applying that layer with node variables (`NODE_DOMAIN`, `NODE_PATH`) |
| `nodes/<path>/flux-system/` | Flux components (pinned) + sync of this node |
| `bootstrap/` | One-time node install; templates used by `just` |

Layers per node:
- `infrastructure`: CRD/controller providers (Helm): traefik, cert-manager, external-secrets, cloudnative-pg.
- `operators`: operators shipped as plain manifests needing layer-1 CRDs: RabbitMQ cluster + topology operators (vendored, `just vendor-rabbitmq`).
- `data`: data services: Postgres cluster `main`, RabbitMQ cluster `main`, per-service databases and users. Ready only when they are (CEL health checks).
- `apps`: everything else. `dependsOn: infrastructure` only if the app uses layer-1 CRDs.

## Node features
Nodes run the same code and differ only by enabled features, declared Cargo-style in `features.yaml`:
```yaml
platform:            # every node, never toggled: CRD providers and operators
  infrastructure: [traefik, cert-manager, external-secrets, cloudnative-pg]
  operators: [rabbitmq-operators]
components:          # toggled by features -> layer
  postgres: data
features:
  postgres: [dep:postgres]
  lados: [postgres, rabbitmq, web]   # codename = set of features
```
A node lists features in `nodes/<path>/node.yaml` (`features: [lados]`). `just features` renders the node's layer kustomizations; never edit them by hand. CI (`just features --check`) fails on unknown names, cycles, missing or stale version files, and out-of-date files.

Services are listed with what they need and enabled by a feature (`svc:<name>`); a need is also a feature, so enabling the service enables Postgres/RabbitMQ:
```yaml
services:
  playground: {needs: [postgres, rabbitmq]}
features:
  playground: [svc:playground]
```

Turning a feature off: remove it from `node.yaml`, delete what the check names, `just features`, one PR. Flux deletes the feature's objects; operators stay (platform) and finalize them. Flux has no deletion order between Kustomizations ([kustomize-controller#301](https://github.com/fluxcd/kustomize-controller/issues/301)), which is why providers are never feature-toggled.

Dropping data: a service leaving a node drops its database and role; a stateful component (`stateful` in `features.yaml`) drops its cluster with all data. CI (`drop-data` workflow, `just dropped`) fails such a PR unless it has label `drop-data`.

New component: `components/<name>/`; a provider goes to `platform`, anything else to `components` + a feature. Per-node chart version in `nodes/<path>/<layer>/<name>.version.yaml`.

Version files: service charts are bumped by the CI bot (`gitops-bump`); third-party charts by Renovate (`alterworld-hub/.github`), which needs a hint above the tag (prefer a datasource with release dates, e.g. the chart's Helm repo, so minimumReleaseAge works):
```yaml
    # renovate: datasource=helm depName=traefik registryUrl=https://traefik.github.io/charts
    tag: 41.7.1
```

## Postgres for a service
One CloudNativePG cluster per node (`main`, namespace `postgres`). Per service: role + database (snake_case of the service name), password generated on the node by ESO (`CreatedOnce`), never in git.

1. Service in `features.yaml` with `needs: [postgres]`, enabled on the node by a feature; `just features`; PR.
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

1. Service with `needs: [rabbitmq]` (same as above).
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
| `just features [--check]` | Render node layers and service objects from features (check: CI mode) |
| `just dropped [base]` | Stateful data this tree drops compared with `base` (default `origin/main`) |
| `just psql [db]` / `just pg-forward` | Admin psql in the node cluster / forward Postgres to localhost:5432 |
| `just mq-admin` / `just mq-forward` | Management UI login / forward AMQP to localhost:5672 |
| `just vendor-rabbitmq <cluster> <topology>` | Re-vendor RabbitMQ operator manifests |
| `just validate` | Render and schema-check all kustomizations (same as CI) |
| `just flux-components <node>` | Re-pin Flux components to the installed CLI version |

## Rules
- Change state only via PR. Merge = deploy.
- Pin every version: chart tags, images by digest.
- Secrets only SOPS-encrypted.
