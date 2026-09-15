# Bootstrap

This page documents the one-time bring-up procedure: building Talos ISOs, forming the HA cluster, and handing management to Argo CD. It assumes familiarity with `kubectl` but no prior cluster installation experience.

## Prerequisites

Install the following tools on the workstation first. `talosctl` must match Talos `v1.14.0` and manages the node OS. `kubectl` must match Kubernetes `v1.37.0` and manages workloads. `kubeseal` encrypts secrets for storage in Git. `git` checks out and updates this repository.

The cluster requires at least 3 Talos nodes. Three is the etcd quorum minimum, and every node is a schedulable control-plane member. This repository was built with 3 VMs (2 in UTM, 1 in Proxmox), all booted from the Talos ISO and bridged onto `10.3.3.0/24`. Any platform works as long as the nodes share L2 adjacency, which ARP-based VIP failover requires. Reserve one address per node (here `.189`, `.190`, and `.192`) through DHCP reservations or an equivalent mechanism, and keep the `.8`, `.9` (LB), and `.10` VIPs free and outside the DHCP pool. A Cloudflare API token scoped to DNS-Edit is required for the DNS-01 challenges, and `dsns.dev`, `seung.dev`, and `mseung.dev` must be delegated to Cloudflare.

## 0. Build Talos ISOs and Boot the VMs

Build the installer ISOs in the Talos Image Factory at `https://factory.talos.dev`. Select version `v1.14.0` and add any required system extensions (extra drivers baked into the image). Build one schematic per CPU architecture: arm64 for the UTM VMs on Apple Silicon, amd64 for the Proxmox VM. The factory records each build as a schematic ID, so the exact image can be reproduced later. Download the resulting ISOs.

**Create the VMs.** Give each VM at least the Talos minimums (2 vCPU, 2 GB RAM, 10 GB disk), with headroom above that because these control-plane nodes also run workloads. Every VM must use bridged networking so each node receives its own LAN address. In UTM, create a new VM, attach the arm64 ISO as a CD drive, set the network interface to bridged mode, and boot from the CD. In Proxmox, upload the amd64 ISO under Datacenter, Storage, ISO Images, then create a VM with the ISO attached and its NIC on the LAN bridge in bridge mode, and boot from the CD.

**First boot.** Each node boots into maintenance mode, requests an address over DHCP, and prints its acquired addresses on the console. Record the three addresses. They become `<node-1/2/3>` in step 3, and they should match the `.189`, `.190`, and `.192` reservations.

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

Replace `<node-1/2/3>` with `.189`, `.190`, and `.192`. For extra nodes, add a `talos/nodes/cp-0N.yaml` hostname file and append the matching line.

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

Install the upstream manifests with server-side apply, which is required because the CRD set is large:

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

For every `*.TEMPLATE.yaml` file, build the plain Secret locally, seal it, and commit only the sealed output. The following example seals the Minecraft config:

```bash
kubectl create secret generic velocity-config -n minecraft \
  --from-file=velocity.toml=./velocity.toml \
  --from-file=forwarding.secret=./forwarding.secret \
  --dry-run=client -o yaml | kubeseal -o yaml > apps/minecraft/velocity-secret.sealed.yaml
```

The currently sealed inputs are the Cloudflare token (`infra/cert-manager/cloudflare-secret`), the Minecraft config (`apps/minecraft/velocity-secret`), and the V2Ray config (`apps/v2ray/v2ray-config`).

## 6. Deploy the Root App

This is the last manually executed command of the setup procedure. It points Argo CD at `argocd/apps` on `main`, and Argo CD installs the rest by itself within about 3 minutes.

```bash
kubectl apply -f argocd/root-app.yaml
```

Open the UI at `https://10.3.3.9` once `argocd-server-lb` receives its IP.
