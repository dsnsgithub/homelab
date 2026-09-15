# Bootstrap

First-time setup: turning three empty virtual machines into a working cluster. Do it once, in order — afterwards you never repeat it, you just push changes to Git and the autopilot applies them. Allow roughly half an hour, most of it waiting.

## Prerequisites

Tools to install on your own computer first:

- `talosctl` — remote control for the Talos operating system (match version `v1.14.0`).
- `kubectl` — remote control for the apps running on the cluster (match version `v1.37.0`).
- `kubeseal` — locks passwords so they can be stored in Git.
- `git` — downloads and uploads this repository.

The environment you need:

- 3 virtual machines (2 in UTM, 1 in Proxmox) started from the Talos installer image, all on the home network with bridged networking.
- Router addresses `.189` / `.190` / `.192` available for the machines; shared addresses `.8`, `.9`, `.10` free and kept out of the router's automatic-assignment pool.
- A Cloudflare login (token) allowed to edit DNS — used once to prove domain ownership for certificates.
- Domain names pointing at Cloudflare: `dsns.dev`, `seung.dev`, `mseung.dev`.

## 1. Download This Repo

```bash
git clone https://github.com/dsnsgithub/homelab/
cd homelab
```

If a working cluster already exists, skip ahead to [step 4](#4-install-the-autopilot).

## 2. Create the Machines' ID Cards

This generates the configuration files (ID cards, keys, addresses) the machines will use. They land in a local `_talos/` folder that is never committed to Git — back it up somewhere safe, because you need it for upgrades and new machines.

```bash
talosctl gen config homelab https://10.3.3.8:6443 \
  --config-patch @talos/controlplane-patch.yaml \
  --output-dir _talos

# Save the master keys for later — do not commit this file
talosctl gen secrets -o _talos/secrets.yaml \
  --from-controlplane-config _talos/controlplane.yaml
```

## 3. Hand Out ID Cards & Start the Cluster

Replace `<node-1/2/3>` with `.189`, `.190`, `.192`. (Adding a fourth machine later works the same way: copy one of the `talos/nodes/cp-0N.yaml` name files and add its line.)

```bash
talosctl apply-config --insecure -n <node-1> \
  --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-01.yaml
talosctl apply-config --insecure -n <node-2> \
  --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-02.yaml
talosctl apply-config --insecure -n <node-3> \
  --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-03.yaml

talosctl config merge _talos/talosconfig
talosctl config endpoint <node-1> <node-2> <node-3>
talosctl config node <node-1> <node-2> <node-3>

# Start the shared decision-making exactly once, on the first machine
talosctl bootstrap -n <node-1>

# Log in through the shared address (works even if one machine is down)
talosctl kubeconfig -n 10.3.3.8
kubectl get nodes -A -o wide
```

Success looks like 3 machines all saying `Ready`. The shared `.8` address can take 30–60 seconds to appear — that is normal.

## 4. Install the Autopilot

This installs Argo CD, the program that watches this repo and installs everything else:

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

> Only relevant if rebuilding on k3s instead of Talos: turn off its built-in address-helper and front door first — this repo brings its own (kube-vip + Traefik on `.9`/`.10`).

## 5. Install the Password Locker

This installs the Sealed Secrets program, which unlocks the encrypted passwords stored in Git:

```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
```

For every blank `*.TEMPLATE.yaml` form, fill in the real values on your computer, lock them with `kubeseal`, and commit only the locked result:

```bash
kubectl create secret generic velocity-config -n minecraft \
  --from-file=velocity.toml=./velocity.toml \
  --from-file=forwarding.secret=./forwarding.secret \
  --dry-run=client -o yaml | kubeseal -o yaml > apps/minecraft/velocity-secret.sealed.yaml
```

Currently locked passwords: the Cloudflare login (`infra/cert-manager/`), the Minecraft config (`apps/minecraft/`), and the VPN config (`apps/v2ray/`).

## 6. Hand the Autopilot Its Map

The last command you ever run by hand for setup — it points Argo CD at this repo, and Argo CD installs the rest by itself (about 3 minutes):

```bash
kubectl apply -f argocd/root-app.yaml
```

Watch progress in the Argo CD website at `https://10.3.3.9`.
