# Operations

## GitOps Workflow

Normal changes follow this loop, and no manual install commands are needed:

1. Edit manifests in `infra/` or `apps/`, or add `argocd/apps/<name>-app.yaml` for a new component.
2. Push to `main`.
3. Argo CD auto-syncs within about 3 minutes. Prune removes deleted objects, and selfHeal reverts manual `kubectl` edits.
4. Verify with `argocd app list` or in the UI at `https://10.3.3.9`.

`argocd/root-app.yaml` is the only object applied by hand after bootstrap. Everything else is a child Application of the root.

## Regenerate Talos Config

After editing `talos/controlplane-patch.yaml`, re-render the configs from the saved master keys in `_talos/secrets.yaml`:

```bash
talosctl gen config homelab https://10.3.3.8:6443 \
  --with-secrets _talos/secrets.yaml \
  --config-patch-control-plane @talos/controlplane-patch.yaml \
  --output-dir _talos
```

## Add a Node

1. Add `talos/nodes/cp-04.yaml` with the new hostname, using the same `HostnameConfig` shape as the existing three files.
2. Regenerate the configs as shown above, then apply the new node config and register it:

```bash
talosctl apply-config --insecure -n <node-4> \
  --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-04.yaml
talosctl config endpoint <node-4>
talosctl config node <node-4>
```

3. Verify membership and consensus with `talosctl etcd status` and `kubectl get nodes`.

## Upgrade Talos and Kubernetes

Upgrade one node at a time and wait for `Ready` between nodes. etcd needs 2 of 3 members online, so upgrading two nodes at once would stall writes:

```bash
talosctl upgrade -n <each-node> --image ghcr.io/siderolabs/installer:vX.Y.Z
```

## Secrets Rotation

Fetch the controller current public certificate with `kubeseal --fetch-cert`, re-seal the secret, and push through Git like any other change. The Cloudflare token lives at `infra/cert-manager/cloudflare-secret.sealed.yaml`. If the controller certificate is ever replaced, re-seal every sealed file, because the old files will stop decrypting.

## Backups

State lives in etcd (replicated 3 ways) and intent lives in this repo. The two irreplaceable local artifacts are `_talos/secrets.yaml` (cluster PKI and credentials) and `talosconfig` (admin access), so keep copies offline. Everything else rebuilds from Git plus the sealed secrets.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `kubectl` cannot reach `10.3.3.8:6443` | Run `talosctl -n <node-ip> get addresses` on each node to confirm the VIP exists, and confirm all NICs are bridged on one L2 segment. |
| VIP `.9` or `.10` does not respond | Run `kubectl -n kube-system get ds kube-vip-ds` and read the pod logs. If the pods are healthy, suspect AP client isolation or a switch filtering gratuitous ARP. |
| Argo CD app is OutOfSync or Degraded | Run `argocd app list` and `kubectl -n argocd get app <name>`. Confirm the revision and path in `root-app.yaml`, and check whether the app needs a sync-wave or ignore-differences rule. |
| Certificate stays NotReady | Run `kubectl -n web-proxy describe cert <name>` and `kubectl describe clusterissuer letsencrypt-prod`. Validate that the Cloudflare token still has the DNS-Edit scope, and read the `cert-manager` controller logs. |
| SealedSecret does not decrypt | The controller certificate may have rotated. Re-fetch the certificate, re-seal the secret, and confirm the sealed object targets the correct namespace and name, because scoping is strict by default. |
| Pod fails on one architecture only | Run `kubectl describe pod`. An `exec format error` or image-pull failure means a single-arch image, so pin a multi-arch tag. |
| UTM VM loses its network after reboot | Re-attach bridged mode in the UTM settings. Talos binds `deviceSelector: physical: true` to the first physical NIC it finds, so a detached interface changes the match. |

## Roadmap

- [x] HA Talos, kube-vip service LB, Argo CD Root App, wildcard TLS, Minecraft, V2Ray and web proxy
- [ ] Immich (`immich.dsns.dev`)
- [ ] T3 Code (`code.dsns.dev`)
- [ ] WireGuard VPN
- [ ] Persistent storage for stateful apps (Longhorn or NFS, still undecided)
- [ ] Backup restore drill (rebuild from `_talos/` and Git on spare VMs)
- [ ] Monitoring (kube-prometheus-stack with alerting)
