# Operations

## Making Changes

`main` is production. Every change goes through a PR, which must pass:

- `validate`: renders and schema-checks every app and preview, and validates the Talos configs. Run locally with `.github/scripts/validate.sh`.
- `preview`: deploys previews if the PR changes a chart with `values-preview.yaml`, and waits for them to become healthy.

On merge, `deploy` applies Talos configs if `talos/` changed, then waits for Argo CD to sync. To force a Talos apply, run the workflow manually with `talos` checked.

Admin pushes to `main` skip the checks but still deploy. Revert to roll back.

## CI Secrets

| Secret | Environments | Contents |
|---|---|---|
| `WG_CONFIG` | `production`, `preview` | WireGuard peer for the runner |
| `KUBECONFIG` | `production`, `preview` | `github-ci` ServiceAccount token (read and refresh Argo CD apps only) |
| `SOPS_AGE_KEY` | `production` | CI age key for `talos/secrets.yaml` (full node access) |

To rotate `SOPS_AGE_KEY`, replace the CI recipient in `.sops.yaml` and run `sops updatekeys talos/secrets.yaml`.

## PR Previews

Charts with `values-preview.yaml` deploy to `<chart>-pr-<number>` and are deleted when the PR closes. Previews can't use LoadBalancer IPs, IngressRoutes, or namespaces other than `.Values.namespace`.

```bash
kubectl -n minecraft-pr-<number> port-forward service/mc-proxy-service 25565:25565
```

## Control Plane Scheduling

`talos-m2` keeps the default control plane taint. `talos-m4` and `talos-raider` run workloads.

Apply Talos changes by hand:

```bash
topf --topfconfig talos/topf.yaml apply
```

## Drain and Undrain a Node

Drain:
```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

Undrain:
```bash
kubectl uncordon <node-name>
```

## Repair a Crashlooping etcd Member

https://docs.siderolabs.com/talos/v1.14/build-and-extend-talos/cluster-operations-and-maintenance/disaster-recovery#prepare-control-plane-nodes

```bash
talosctl -n <IP> reset --graceful=false --reboot --system-labels-to-wipe=EPHEMERAL
```
