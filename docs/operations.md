# Operations

## GitOps Workflow

1. Edit manifests in `infra/` or `apps/`, or add `argocd/apps/<name>-app.yaml`.
2. Push to `main`.
3. Argo CD auto-syncs in ~3 min. No `kubectl apply`.
4. Verify: `argocd app list` or UI at `https://10.3.3.9`.

`argocd/root-app.yaml` is the only object applied by hand after bootstrap; everything else is a child Application.

## Regenerate Talos Config

After editing `talos/controlplane-patch.yaml`:

```bash
talosctl gen config homelab https://10.3.3.8:6443 \
  --with-secrets _talos/secrets.yaml \
  --config-patch-control-plane @talos/controlplane-patch.yaml \
  --output-dir _talos
```

## Add a Node

1. Add `talos/nodes/cp-04.yaml` with the new hostname.
2. Regenerate (above), then:

```bash
talosctl apply-config --insecure -n <node-4> \
  --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-04.yaml
talosctl config endpoint <node-4>
talosctl config node <node-4>
```

3. Verify: `talosctl etcd status`, `kubectl get nodes`.

## Upgrade Talos / Kubernetes

One node at a time, waiting for `Ready` between nodes. Never upgrade two etcd members concurrently:

```bash
talosctl upgrade -n <each-node> --image ghcr.io/siderolabs/installer:vX.Y.Z
```

## Secrets Rotation

Re-seal with the current controller cert (`kubeseal --fetch-cert`) and re-apply via Git. Cloudflare token: `infra/cert-manager/cloudflare-secret.sealed.yaml`.

## Backups

etcd is the source of truth (3-way replicated). Keep `_talos/secrets.yaml` + `talosconfig` offline. All cluster state beyond that rebuilds from this repo + sealed secrets.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `kubectl` cannot reach `10.3.3.8:6443` | `talosctl -n <node-ip> get addresses`; VIP present? Same L2 / bridged? |
| VIP `.9` / `.10` silent | `kubectl -n kube-system get ds kube-vip-ds`; logs; gratuitous ARP blocked by switch/AP isolation? |
| Argo CD out of sync | `argocd app list`; `kubectl -n argocd get app`; `root-app.yaml` revision/path |
| TLS not issuing | `kubectl -n web-proxy get cert`; `describe clusterissuer letsencrypt-prod`; Cloudflare token; `cert-manager` logs |
| Sealed secret won't decrypt | Controller cert rotated? Re-seal with `--fetch-cert` |
| Mixed-arch pod errors | `kubectl describe pod` — exec format / image pull errors mean missing arch manifest; pin multi-arch tags |
| UTM VM loses net after reboot | Re-attach bridged interface; Talos `deviceSelector: physical: true` picks first physical NIC |

## Roadmap

- [x] HA Talos, kube-vip, Argo CD GitOps, wildcard TLS, Minecraft, V2Ray
- [ ] Immich (`immich.dsns.dev`)
- [ ] T3 Code (`code.dsns.dev`)
- [ ] WireGuard VPN
- [ ] Persistent storage (Longhorn / NFS — TODO)
- [ ] Backup verification + restore drill
- [ ] Monitoring / alerting
