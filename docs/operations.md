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

## WireGuard VPN (wg-easy)

`apps/wireguard/` runs wg-easy (v15): WireGuard plus a web UI for peer management. Unlike the rest of the homelab it is stateful by design — server keys, the SQLite database and peer configs live in the `wgeasy-data` PVC (1Gi via the `local-path` provisioner, data under `/opt/local-path-provisioner` on whichever node holds the volume). Deleting the PVC wipes every peer.

First-time setup (needs `kubectl`, `kubeseal` on your computer):

```bash
ADMIN_PASSWORD="$(openssl rand -base64 24)"
echo "save this somewhere offline: $ADMIN_PASSWORD"
kubectl create secret generic wgeasy-auth -n wireguard-vpn \
  --from-literal=admin-password="$ADMIN_PASSWORD" \
  --dry-run=client -o yaml > apps/wireguard/wireguard-secret.plain.yaml
kubeseal --format yaml --controller-name sealed-secrets-controller --controller-namespace kube-system \
  < apps/wireguard/wireguard-secret.plain.yaml > apps/wireguard/wireguard-secret.sealed.yaml
git add apps/wireguard/wireguard-secret.sealed.yaml && git commit -m "wireguard: seal admin password" && git push
# Argo CD syncs within ~3 minutes. The INIT_* vars in the Deployment run the
# onboarding wizard unattended on first boot only; afterwards peers are
# managed in the UI, and changing INIT_* has no effect unless the PVC is deleted.
```

Manage peers (UI is ClusterIP-only, not exposed publicly):

```bash
kubectl -n wireguard-vpn port-forward deploy/wireguard 51821:51821
# open http://localhost:51821, log in as admin
```

Notes: replicas must stay 1 (the PVC is ReadWriteOnce and UDP has no session affinity); the LoadBalancer VIP is `10.3.3.11`, keep it outside the DHCP pool; WAN access needs a one-time UDP 51820 port-forward on the router to `10.3.3.11`, LAN peers connect to it directly. Client defaults are a split tunnel (VPN + LAN + pod + service CIDRs) with cluster CoreDNS; per-client full-tunnel and DNS changes happen in the UI. If the tunnel comes up but peers get no traffic, the likely cause is the missing `net.ipv4.conf.all.src_valid_mark=1` sysctl, which Talos kubelets reject by default — allow-list it via the Talos machine config. To expose the UI publicly later, add an ExternalName Service + IngressRoute in `apps/web-proxy` (same pattern as `vray.dsns.dev`) and drop `INSECURE` from the Deployment.
