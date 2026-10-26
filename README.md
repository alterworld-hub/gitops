# gitops

Desired state of every node. Flux on each node pulls `nodes/<node-path>` (read-only). CI never touches nodes.

Conventions: [alterworld-hub/.github](https://github.com/alterworld-hub/.github/blob/main/CONVENTIONS.md).

## Layout
| Path | Holds |
|---|---|
| `platform/` | Components identical on every node (Traefik, ...) |
| `nodes/<path>/` | One node: Flux install, sync target, node variables |
| `nodes/<path>/flux-system/` | Flux components (pinned) + GitRepository/Kustomization for this node |
| `bootstrap/` | One-time node install |

Node variables are injected into `platform/` via Flux `postBuild.substitute` (e.g. `NODE_DOMAIN`).

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
