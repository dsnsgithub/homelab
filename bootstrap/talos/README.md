# Homelab OS-to-apps bootstrap (Talos Linux)

Everything from bare metal to workloads, with each layer's desired state in
git:

| Layer | Source of truth | Applied by |
|---|---|---|
| OS + Kubernetes | patches + `bootstrap/versions.env`, plus committed SOPS-encrypted full configs in `machines/` | `gen-config.sh` → `encrypt.sh` → `apply.sh` |
| ArgoCD | pinned `extraManifests` URL in `controlplane-patch.yaml` | Talos, automatically |
| sealed-secrets + root app | `bootstrap/bootstrap.sh` + `versions.env` | you, once per cluster |
| platform + apps | `argocd/`, `charts/` | ArgoCD root app, continuously |

## Prereqs

- `talosctl` matching `TALOS_VERSION` in `bootstrap/versions.env`.
- Talos `metal-amd64.iso` for that version (GitHub release assets, or the
  [Image Factory](https://factory.talos.dev/) if you need system extensions).
- The TODOs in `nodeN.yaml` filled in: interface name, static IPs, gateway,
  install disk. The defaults assume `eth0`, `10.3.3.21-23/24`, gw `10.3.3.1`,
  `/dev/sda`.

## Rebuild / first install

```bash
cd bootstrap/talos

# 1. Generate configs (output has secrets → gitignored, regenerate freely).
./gen-config.sh

# 2. Boot each node from the ISO, note its maintenance (DHCP) IP, then:
./apply-node.sh node1.yaml <node1-maintenance-ip>
./apply-node.sh node2.yaml <node2-maintenance-ip>
./apply-node.sh node3.yaml <node3-maintenance-ip>
# Nodes wipe their disks, install, and reboot onto static IPs.
# (On later rebuilds you can skip gen/apply-node and go straight from the
# committed encrypted configs — see "Fully declarative machine configs".)

# 3. Bootstrap etcd once (any one node, its STATIC ip):
export TALOSCONFIG=$PWD/talosconfig
talosctl -n 10.3.3.21 bootstrap

# 4. Get admin access, wait for healthy:
talosctl -n 10.3.3.21 -e 10.3.3.21 config endpoint 10.3.3.21 10.3.3.22 10.3.3.23
talosctl -n 10.3.3.21 -e 10.3.3.21 kubeconfig ~/.kube/config
talosctl -n 10.3.3.21 health  # or: kubectl get nodes (VIP 10.3.3.8 floats once a leader exists)

# 5. Day-1 platform (from repo root):
../bootstrap.sh
```

ArgoCD arrives via `extraManifests`; `bootstrap.sh` adds the pinned
sealed-secrets controller and the root app. Then create the `github-token`
and notifications PAT secrets (README: Staging / GitHub sync statuses) and
back up `talosconfig` somewhere safe (password manager, encrypted USB).

## Migrating from the old (non-Talos) cluster

Two gotchas, both from new cryptographic identity:

1. **Sealed secrets won't decrypt.** The fresh controller generates a new
   key. Before ArgoCD syncs apps, restore the OLD cluster's key:
   ```bash
   # on the OLD cluster:
   kubectl get secret -n kube-system sealed-secrets-key -o yaml > sealed-secrets-key.backup.yaml
   # on the NEW cluster, BEFORE apps sync (or re-seal everything and commit):
   kubectl apply -f sealed-secrets-key.backup.yaml
   kubectl -n kube-system rollout restart deploy/sealed-secrets-controller
   ```
   Guard that backup like a password — it decrypts every secret in git.
2. **kube-vip's control-plane role is retired.** Talos owns `10.3.3.8`
   natively now. After migration, set `controlPlane.enabled=false` in
   `charts/kube-vip/values.yaml` (keep services for `10.3.3.9/.10/.11`) —
   otherwise two systems ARP for the same VIP.

## Fully declarative machine configs (SOPS)

The patches above are the human-editable intent, but the *complete* machine
configs — secrets included — also live in git, age-encrypted under
`machines/*.sops.yaml` (creation rules in the repo-root `.sops.yaml`).
Nothing secret-bearing is ever committed in plaintext.

One-time age setup:

```bash
age-keygen -o ~/.config/sops/age/keys.txt  # prints "public key: age1..."
# paste the PUBLIC half into .sops.yaml (replacing the TODO), commit.
# Guard the PRIVATE half like talosconfig itself.
```

Snapshot configs to git (after any patch/version change):

```bash
cd bootstrap/talos
./gen-config.sh   # re-render from patches (proves they still apply)
./encrypt.sh      # per-node bake + age-encrypt -> machines/*.sops.yaml
git add machines/ && git commit -m "talos: snapshot machine configs"
```

Apply/upgrade straight from the committed files — decrypted only into a
temp file sops cleans up, never your disk:

```bash
./apply.sh machines/cp1.sops.yaml <maintenance-ip> --insecure  # reinstall
./apply.sh machines/cp1.sops.yaml 10.3.3.21                    # reconfigure
./edit.sh machines/cp1.sops.yaml                               # small tweaks
```

Day-2 Talos upgrades stay declarative: bump `TALOS_VERSION`, re-run
`gen-config.sh` + `encrypt.sh`, commit, then per node
`talosctl upgrade --image ghcr.io/siderolabs/installer:<new>` — or decrypt
and diff first to see exactly what changes.

## Day-2: upgrades (also declarative)

- **Talos OS/Kubernetes patch/minor:** bump `TALOS_VERSION` in
  `bootstrap/versions.env`, download the matching `talosctl`, regenerate
  (`./gen-config.sh` — proves the patches still apply), then per node:
  `talosctl -n <node> upgrade --image ghcr.io/siderolabs/installer:<new>`.
  Kubernetes upgrades: `talosctl -n <node> upgrade-k8s --to <ver>` (check the
  Talos release notes for the supported skew first).
- **ArgoCD / sealed-secrets:** bump `versions.env`, re-run
  `bootstrap/bootstrap.sh`.
- **Everything else:** normal GitOps — commit to `main`, ArgoCD syncs.

## What stays manual (honestly)

- Flashing/booting the ISO, reading maintenance IPs off consoles (unless you
  add PXE/iPXE netboot later — the patches work unchanged).
- `talosconfig` + `sealed-secrets-key` backups (secret material by nature).
- GitHub PATs (gitignored `*.plain.yaml` pattern, applied with kubectl).
- The hardware, BIOS, DHCP reservations and DNS underneath it all.
