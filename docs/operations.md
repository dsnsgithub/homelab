# Operations

## GitOps Workflow

Normal changes follow this loop, and no manual install commands are needed:

1. Edit manifests in `infra/` or `apps/`, or add `argocd/apps/<name>-app.yaml` for a new component.
2. Push to `main`.
3. Argo CD auto-syncs within about 3 minutes. Prune removes deleted objects, and selfHeal reverts manual `kubectl` edits.
4. Verify with `argocd app list` or in the UI at `https://10.3.3.9`.

`argocd/root-app.yaml` is the only object applied manually after bootstrap. Everything else is a child Application of the root.

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

## Secrets

The two irreplaceable local artifacts are `_talos/secrets.yaml` (cluster PKI and credentials) and `talosconfig` (admin access), so keep copies offline. Everything else rebuilds from Git plus the sealed secrets.

## WireGuard VPN

The server in `apps/wireguard/` is completely stateless: no PVCs, no hostPath, nothing on disk. Its identity (server key + peer list) lives in the `wireguard-config` SealedSecret; the initContainer renders `wg0.conf` into an in-memory `emptyDir` at every Pod start. Back up `apps/wireguard/.peers/` (gitignored peer `.conf` files with private keys) offline alongside the Talos artifacts.

First-time setup (needs `wireguard-tools`, `kubectl`, `kubeseal` on your computer):

```bash
./apps/wireguard/gen-wireguard-secret.sh --peers laptop,phone --seal
git add apps/wireguard/wireguard-secret.sealed.yaml && git commit -m "wireguard: seal initial peers" && git push
# Argo CD syncs within ~3 minutes; verify with:
kubectl -n wireguard-vpn exec deploy/wireguard -c wireguard -- wg show wg0
```

Add a peer later by re-running with the FULL list (the existing server key is reused, so current peers keep working):

```bash
./apps/wireguard/gen-wireguard-secret.sh --peers laptop,phone,tablet --seal
```

Notes: replicas must stay 1 (two pods would share one server key/IP and UDP has no session affinity); the LoadBalancer VIP is `10.3.3.11`, keep it outside the DHCP pool; WAN access needs a one-time UDP 51820 port-forward on the router to `10.3.3.11`, LAN peers connect to it directly. Client configs default to a split tunnel (VPN + homelab CIDRs only); change `AllowedIPs` to `0.0.0.0/0, ::/0` in the peer `.conf` for a full tunnel.
