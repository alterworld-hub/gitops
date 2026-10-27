# gitops

Desired state of every node. Flux on each node pulls `nodes/<node-path>` (read-only). CI never touches nodes.

Conventions: [alterworld-hub/.github](https://github.com/alterworld-hub/.github/blob/main/CONVENTIONS.md).

## Layout
| Path | Holds |
|---|---|
| `components/<name>/` | Every deployable component, same shape: namespace, source, HelmRelease. Version placeholder only |
| `nodes/<path>/<layer>/` | Components enabled on the node (kustomization) + `<name>.version.yaml` per component |
| `nodes/<path>/<layer>.yaml` | Flux Kustomization applying that layer with node variables (`NODE_DOMAIN`, `NODE_PATH`) |
| `nodes/<path>/flux-system/` | Flux components (pinned) + sync of this node |
| `bootstrap/` | One-time node install; templates used by `just` |

Layers per node:
- `infrastructure`: CRD/controller providers (Helm): traefik, cert-manager, external-secrets, cloudnative-pg.
- `operators`: operators shipped as plain manifests needing layer-1 CRDs: RabbitMQ cluster + topology operators (vendored, `just vendor-rabbitmq`).
- `data`: data services: Postgres cluster `main`, RabbitMQ cluster `main`, per-service databases and users. Ready only when they are (CEL health checks).
- `apps`: everything else. `dependsOn: infrastructure` only if the app uses layer-1 CRDs.

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

## Commands
| | |
|---|---|
| `just local-up` | k3d node `local` + Flux; Traefik dashboard: http://traefik.local.alterworld-hub.localhost:8080/dashboard/ |
| `just local-down` | Delete it |
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
