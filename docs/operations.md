# Operations

Everything after setup: changing apps, growing the cluster, and fixing problems.

## Everyday Changes

The normal loop — no manual install commands needed:

1. Edit files in `infra/` or `apps/`, or add a new `argocd/apps/<name>-app.yaml` for something new.
2. Push to `main`.
3. Argo CD notices within ~3 minutes and applies the change by itself.
4. Check it worked: run `argocd app list` or open `https://10.3.3.9`.

`argocd/root-app.yaml` is the only thing ever installed by hand (during setup). Everything else flows from it automatically.

## Refreshing the OS Settings

After editing the shared OS settings in `talos/controlplane-patch.yaml`, rebuild the ID cards from your saved master keys:

```bash
talosctl gen config homelab https://10.3.3.8:6443 \
  --with-secrets _talos/secrets.yaml \
  --config-patch-control-plane @talos/controlplane-patch.yaml \
  --output-dir _talos
```

## Add a Machine

1. Create `talos/nodes/cp-04.yaml` containing the new machine's name.
2. Rebuild the ID cards (above), then hand the new machine its card and introduce it:

```bash
talosctl apply-config --insecure -n <node-4> \
  --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-04.yaml
talosctl config endpoint <node-4>
talosctl config node <node-4>
```

3. Confirm it joined: `talosctl etcd status` (the shared decision-making is healthy) and `kubectl get nodes` (shows `Ready`).

## Updating Talos / Kubernetes

Update one machine at a time and wait until it says `Ready` before touching the next. Never update two at once: the machines vote on every decision, and two offline machines out of three means no majority.

```bash
talosctl upgrade -n <each-machine> --image ghcr.io/siderolabs/installer:vX.Y.Z
```

## Changing Passwords

Edit the values, re-lock with the cluster's current key (`kubeseal --fetch-cert`), and push via Git like any other change. The Cloudflare login lives at `infra/cert-manager/cloudflare-secret.sealed.yaml`.

## Backups

The shared decision log (called etcd) is automatically copied on all 3 machines — that plus this repo is the whole system. The two things to keep offline somewhere safe are `_talos/secrets.yaml` (master keys) and `talosconfig` (admin login). With those plus this repo, the cluster can be rebuilt from scratch.

## When Something Breaks

| What you see | What to check (plain words first, command after) |
|---------|-------|
| Apps unreachable at `10.3.3.8:6443` | Is the shared control address up? Check each machine's addresses and confirm all VMs are bridged on the same home network: `talosctl -n <machine-address> get addresses` |
| `.9` / `.10` websites silent | Is the address-moving helper alive? Look at its copies and logs — the home router may also block machines from claiming addresses: `kubectl -n kube-system get ds kube-vip-ds` |
| Argo CD shows an app out of sync | Is it a real problem or just mid-sync? Compare the app list and confirm the repo/branch/path in `root-app.yaml`: `argocd app list` |
| Website has no HTTPS certificate | Are certificates being issued? Check certificate status, the issuer, the Cloudflare login, and the issuer's logs: `kubectl -n web-proxy get cert` |
| A locked password won't unlock | Was the cluster's key replaced? Re-lock the password with the current key (`kubeseal --fetch-cert`) and push again |
| App crashes on one chip family | Does the app support both Apple and PC chips? Look at the pod description — "exec format" or image-pull errors mean a one-chip-only image: `kubectl describe pod` |
| UTM machine loses network after reboot | Did the virtual network cable come unplugged? Re-attach bridged mode in UTM — Talos always picks the first physical network card |

## Roadmap

- [x] Self-healing cluster, address failover, autopilot installs, automatic HTTPS, Minecraft, V2Ray
- [ ] Immich (`immich.dsns.dev`)
- [ ] T3 Code (`code.dsns.dev`)
- [ ] WireGuard VPN
- [ ] Shared storage for apps with data (options: Longhorn / NFS — TODO)
- [ ] Backup tested with a real restore drill
- [ ] Health monitoring + alerts
