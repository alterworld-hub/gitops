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
| `bootstrap/` | One-time node install |

Layers per node:
- `infrastructure`: CRD/controller providers (traefik; later operators).
- `apps`: everything else. `dependsOn: infrastructure` only if the app uses layer-1 CRDs.

Version files: service charts are bumped by the CI bot (`gitops-bump`); third-party charts by PR.

## Commands
| | |
|---|---|
| `just local-up` | k3d node `local` + Flux; Traefik dashboard: http://traefik.local.alterworld-hub.localhost:8080/dashboard/ |
| `just local-down` | Delete it |
| `just validate` | Render and schema-check all kustomizations (same as CI) |
| `just flux-components <node>` | Re-pin Flux components to the installed CLI version |

## Rules
- Change state only via PR. Merge = deploy.
- Pin every version: chart tags, images by digest.
- Secrets only SOPS-encrypted.
