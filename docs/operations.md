# Operations

## Making Changes

`main` is production. Every change goes through a PR, which must pass:

- `talos`: `talosctl validate` on the rendered machine configs.
- `diff`: `argocd app diff --server-side-diff` for every production app at the PR's commit, commented on the PR.
- `preview`: deploys previews if the PR changes a chart with `values-preview.yaml`, then `argocd app wait`.

On merge, `deploy` runs `topf apply` if `talos/` changed, then `argocd app wait`. To force a Talos apply, run the workflow manually with `talos` checked.

Admin pushes to `main` skip the checks but still deploy. Revert to roll back.

## CI Secrets

| Secret | Environments | Contents |
|---|---|---|
| `WG_CONFIG` | `production`, `preview` | WireGuard peer for the runner |
| `ARGOCD_AUTH_TOKEN` | `production`, `preview` | Read-only `github-ci` Argo CD account (`charts/argocd-config`) |
| `SOPS_AGE_KEY` | `production` | CI age key for `talos/secrets.yaml` (full node access) |

To rotate `SOPS_AGE_KEY`, replace the CI recipient in `.sops.yaml` and run `sops updatekeys talos/secrets.yaml`.

## PR Previews

Charts with `values-preview.yaml` deploy to `<chart>-pr-<number>` and are deleted when the PR closes. Previews can't leave `*-pr-*` namespaces or create IngressRoutes, Certificates, or LoadBalancer/NodePort Services.

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
