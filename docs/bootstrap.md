# Bootstrap

Install the following tools on your own computer first.

| Tool | Version | Purpose |
|------|---------|---------|
| `talosctl` | Must match Talos `v1.14.0` | Node OS management |
| `kubectl` | Must match Kubernetes `v1.37.0` | Workload management |
| `kubeseal` | Any recent release | Secret encryption for Git |

At least 3 Talos nodes are required (the etcd quorum minimum; every node is a schedulable control-plane member). This cluster runs 3 bridged VMs (2 UTM, 1 Proxmox) on `10.3.3.0/24`. Any platform works if the nodes share L2 adjacency, which ARP-based VIP failover requires. Reserve one address per node and keep the `.8`, `.9` (LB), `.10` (LB), and `.11` (LB) VIPs outside the DHCP pool. DNS-01 challenges require a Cloudflare DNS-Edit token, with `dsns.dev`, `seung.dev`, and `mseung.dev` delegated to Cloudflare.

## 0. Build Talos ISOs and Boot the VMs

Visit https://factory.talos.dev and download the ISOs for your platform, adding system extensions as needed.

Create the VMs by attaching the matching ISO. If you are using UTM, enable **Apple Virtualization** instead of QEMU to prevent etcd corruption on power loss and use **bridged** networking to give the VMs their own IP.

On first boot, each node enters maintenance mode, displaying a DHCP address. Those IPs become `<node-1/2/3>` in step 3.

## 1. Clone

```bash
git clone https://github.com/dsnsgithub/homelab/
cd homelab
```

If you are rebuilding onto an existing healthy cluster, skip to [step 4](#4-install-argo-cd).

## 2. Generate Talos Config

`talosctl gen config` renders per-node machine configs from the patch in `talos/`. `gen secrets` creates the shared cluster credentials (certificate authority and etcd keys). Output lands in the local-only `_talos/` folder. Back that folder up, because it cannot be regenerated identically.

```bash
talosctl gen config homelab https://10.3.3.8:6443 \
  --config-patch @talos/controlplane-patch.yaml \
  --output-dir _talos

# Keep this file for upgrades and new nodes. Do not commit it.
talosctl gen secrets -o _talos/secrets.yaml \
  --from-controlplane-config _talos/controlplane.yaml
```

## 3. Apply Config and Bootstrap etcd

`apply-config --insecure` pushes the machine config to a fresh node and sets its hostname from the `--config-patch` file. Run `bootstrap` exactly once on the first node to initialize etcd. The remaining nodes join the existing member set. The rest of the commands import the generated config and point `talosctl` at the new nodes.

Replace `<node-1/2/3>` with the IPs for your nodes. For extra nodes, add a `talos/nodes/cp-0N.yaml` hostname file and check out [Operations](docs/operations.md) for more information.

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

# Initialize etcd exactly once, on the first node.
talosctl bootstrap -n <node-1>

# Fetch kubeconfig through the HA VIP, so access survives any single node loss.
talosctl kubeconfig -n 10.3.3.8
kubectl get nodes -A -o wide
```

Expect three `Ready` control-plane nodes. The `.8` VIP can take 30 to 60 seconds to appear while Talos elects a holder.

## 4. Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## 5. Install Sealed Secrets

The controller decrypts `SealedSecret` objects into regular Secrets at sync time. `kubeseal` runs locally against the cluster public certificate and performs the encryption. A fresh cluster generates a fresh controller certificate, so every secret must be re-sealed when rebuilding from scratch.

```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
```

For every `*.TEMPLATE.yaml` file, build the plain Secret locally, seal it, and commit only the sealed output. Each `*.TEMPLATE.yaml` documents its own sealing command. Only genuinely secret values are sealed: app configs live in plaintext `ConfigMaps` next to them, and the secret is wired in at startup (an initContainer renders V2Ray's `config.json`; Limbo and Velocity consume the forwarding secret natively via env/file).

The currently sealed inputs are the Cloudflare token (`infra/cert-manager/cloudflare-secret.sealed.yaml`), the Minecraft forwarding secret (`apps/minecraft/velocity-secret.sealed.yaml`), and the V2Ray client ID (`apps/v2ray/v2ray-secret.sealed.yaml`).

## 6. Deploy the Root App

This is the last manually executed command of the setup procedure. It points Argo CD at `argocd/apps` on `main`, and Argo CD installs the rest by itself within about 3 minutes.

```bash
kubectl apply -f argocd/root-app.yaml
```

Open the UI at `https://10.3.3.9` once `argocd-server-lb` receives its IP.
