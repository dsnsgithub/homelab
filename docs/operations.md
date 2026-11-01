# Operations

## Making Changes

`main` is production. Every change goes through a PR, which must pass:

- `render`: renders `bootstrap/` and runs `talosctl validate` on the rendered machine configs.
- `diff`: [argocd-diff-preview](https://github.com/dag-andersen/argocd-diff-preview), commented on the PR.
- `preview`: deploys previews if the PR changes a chart with `values-preview.yaml`, then `argocd app wait`.

On merge, `deploy` runs `topf apply` in try mode, then for real, applies `bootstrap/` (Argo CD and sealed-secrets), then `argocd app wait`. Talos changes that need a reboot can't use try mode, so apply those by hand.

To undo a merge, revert it. Admin pushes to `main` skip the checks but still deploy.

Versions are pinned everywhere; [Renovate](https://docs.renovatebot.com/) opens PRs to bump them.

## CI Secrets

| Secret | Environments | Contents |
|---|---|---|
| `WG_CONFIG` | `production`, `preview` | WireGuard peer for the runner, with `AllowedIPs = 10.3.3.0/24` and no `DNS` |
| `ARGOCD_AUTH_TOKEN` | `production`, `preview` | Read-only `github-ci` Argo CD account (`bootstrap/argocd`) |
| `SOPS_AGE_KEY` | `production` | CI age key for `talos/secrets.yaml` and `bootstrap/sealed-secrets/keys.yaml` (full cluster access) |

To rotate `SOPS_AGE_KEY`, replace the CI recipient in `.sops.yaml` and run `sops updatekeys` on both files.

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
