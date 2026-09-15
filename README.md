# Homelab — HA Talos Kubernetes with GitOps

A production-style homelab running a 3-node, highly-available Talos Kubernetes cluster, fully managed as code with Argo CD.

Everything in this repository is declarative: cluster configuration, infrastructure controllers, TLS, networking, and workloads. The cluster is bootstrapped once by hand, then all Day-2 changes flow through Git → Argo CD.

```text
GitHub (main) ──► Argo CD Root App ──► Infra + Apps
                                         ├── kube-vip (LoadBalancer VIPs)
                                         ├── cert-manager (Let's Encrypt / Cloudflare DNS-01)
                                         ├── Traefik (ingress, 10.3.3.10)
                                         ├── Sealed Secrets (encrypted secrets in Git)
                                         ├── Minecraft (Velocity + Limbo, mc.dsns.dev)
                                         ├── V2Ray VPN (vray.dsns.dev)
                                         └── Web Proxy (Traefik IngressRoutes → LAN backends)
```

---

## Table of Contents

- [Architecture](#architecture)
- [Hardware Inventory](#hardware-inventory)
- [Network](#network)
- [Software Stack](#software-stack)
- [Repository Layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Bootstrap](#bootstrap)
  - [1. Clone](#1-clone)
  - [2. Generate Talos Config](#2-generate-talos-config)
  - [3. Apply Config & Bootstrap etcd](#3-apply-config--bootstrap-etcd)
  - [4. Install Argo CD](#4-install-argo-cd)
  - [5. Install Sealed Secrets](#5-install-sealed-secrets)
  - [6. Deploy the Root App](#6-deploy-the-root-app)
- [GitOps Workflow](#gitops-workflow)
- [Virtual IPs & Load Balancers](#virtual-ips--load-balancers)
- [DNS & TLS](#dns--tls)
- [Applications](#applications)
- [Day-2 Operations](#day-2-operations)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)

---

## Architecture

- **3x control-plane nodes, all schedulable.** There are no dedicated workers. Taints for `node-role.kubernetes.io/control-plane` are removed in `talos/controlplane-patch.yaml` so workloads run on the control-plane nodes. This is intentional for a small HA homelab and requires a minimum of 3 nodes for etcd quorum.
- **Immutable OS:** Talos Linux (no SSH, no shell — all management via `talosctl` API).
- **HA API:** Talos built-in VIP `10.3.3.8` fronts `kube-apiserver:6443`. kube-vip runs in service mode (`svc_enable=true`, `cp_enable=false`) and only announces LoadBalancer Services.
- **GitOps:** Argo CD Root App watches `argocd/apps/` on `main` and auto-syncs (prune + self-heal, ~3 min poll).
- **Edge:** Traefik (2 replicas) terminates TLS and routes to in-cluster services and external LAN backends via headless Services + EndpointSlices.
- **Secrets:** Sealed Secrets. Only `*.sealed.yaml` is committed. Templates (`*.TEMPLATE.yaml`) document the expected shape.

Current live state:

```text
~ ❯ kubectl get nodes -A -o wide
NAME           STATUS   ROLES           AGE    VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE          KERNEL-VERSION          CONTAINER-RUNTIME
talos-m2       Ready    control-plane   144m   v1.37.0   10.3.3.9      <none>        Talos (v1.14.0)   6.18.48-talos (arm64)   containerd://2.3.4
talos-m4       Ready    control-plane   143m   v1.37.0   10.3.3.190    <none>        Talos (v1.14.0)   6.18.48-talos (amd64*)  containerd://2.3.4
talos-raider   Ready    control-plane   143m   v1.37.0   10.3.3.192    <none>        Talos (v1.14.0)   6.18.48-talos (amd64)   containerd://2.3.4
```

> `talos-m4` reports `amd64` in the sample above — expected to be `arm64` (Apple Silicon UTM guest). Verify with `kubectl get node talos-m4 -o jsonpath='{.status.nodeInfo.architecture}'` and correct the inventory below if needed.

---

## Hardware Inventory

| Hostname | Host hardware | Virtualization | Talos VM allocation | Node IP | Arch | Role |
|----------|---------------|----------------|---------------------|---------|------|------|
| `talos-m2` | Mac mini (M2) — _TODO: RAM / disk_ | UTM, bridged networking | _TODO: vCPU / RAM / disk_ | `10.3.3.9` | arm64 | control-plane (schedulable) |
| `talos-m4` | Mac mini (M4) — _TODO: RAM / disk_ | UTM, bridged networking | _TODO: vCPU / RAM / disk_ | `10.3.3.190` | arm64* | control-plane (schedulable) |
| `talos-raider` | Raider (Proxmox node, borrowed from separate Proxmox cluster) — _TODO: CPU / RAM / disk_ | Proxmox VE VM, bridged networking | _TODO: vCPU / RAM / disk_ | `10.3.3.192` | amd64 | control-plane (schedulable) |

Notes:

- All three VMs use **bridged networking** so each Talos node gets a first-class LAN IP on `10.3.3.0/24` (required for ARP-based VIP failover).
- Mixed-architecture cluster (arm64 + amd64) — all deployed images must be multi-arch. Current images (`itzg/mc-proxy`, `v2fly/v2fly-core`, `busybox`, Traefik, cert-manager, kube-vip) all ship multi-arch manifests.
- `talos-raider` is borrowed from another Proxmox cluster. If it is reclaimed, etcd loses quorum (2/3 → 1/3 is not quorum). Replace it before decommissioning — see [Day-2 Operations](#day-2-operations).

> **To complete this table, please provide:** host RAM/disk for both Mac minis, vCPU/RAM/disk allocated to each UTM VM, and Raider host specs + Proxmox VM allocation (CPU type, RAM, disk size/type).

---

## Network

| Address | Purpose | Announced by |
|---------|---------|--------------|
| `10.3.3.8` | Kubernetes API (`https://10.3.3.8:6443`), Talos VIP | Talos built-in VIP (`talos/controlplane-patch.yaml`) |
| `10.3.3.9` | Argo CD Server LoadBalancer (HTTP 80 / HTTPS 443) | kube-vip DaemonSet (ARP leader election) |
| `10.3.3.10` | Shared edge VIP: Traefik + Minecraft | kube-vip DaemonSet (ARP leader election) |

Details:

- Subnet: `10.3.3.0/24`. Node DHCP is enabled in `talos/controlplane-patch.yaml` with a static VIP layered on the physical interface (`deviceSelector: physical: true`).
- kube-vip (`ghcr.io/kube-vip/kube-vip:v1.0.4`) runs as a DaemonSet in `kube-system` with `hostNetwork: true`, ARP mode, Raft-free leader election (`vip_leaderelection=true`, lease 5s / renew 3s / retry 1s). If the leader fails, a surviving node sends gratuitous ARP and takes the VIP.
- Traefik Service pins `loadBalancerIP: 10.3.3.10` with 2 replicas for edge HA. HTTP→HTTPS redirect is enforced (`web → websecure`).
- Bridged mode is required on UTM and Proxmox. NAT or host-only networking will break ARP advertisement and VIP failover.

---

## Software Stack

| Layer | Component | Version / source | Notes |
|-------|-----------|------------------|-------|
| OS | Talos Linux | `v1.14.0`, kernel `6.18.48-talos` | Immutable, API-driven |
| Kubernetes | kube-apiserver / kubelet | `v1.37.0` | etcd quorum across 3 CP nodes |
| Runtime | containerd | `2.3.4` | |
| Cluster VIP | Talos built-in VIP | `10.3.3.8` | API HA |
| Service LB | kube-vip | `v1.0.4` | ARP, service mode only |
| GitOps | Argo CD | `stable` manifest | Root App auto-sync, prune + selfHeal |
| Ingress | Traefik | Helm via Argo CD, `values.yaml` pins `.10` | 2 replicas |
| TLS | cert-manager + Let's Encrypt prod | DNS-01 via Cloudflare | Wildcard certs, auto-renew |
| Secrets | Bitnami Sealed Secrets | `controller.yaml` (latest) + `kubeseal` CLI | Encrypted in Git |
| Game | Velocity proxy (`itzg/mc-proxy:java25`) + Limbo | MC `26.2` | 2 replicas, TCP+UDP 25577 |
| VPN | V2Ray (`v2fly/v2fly-core`) | 2 replicas | `vray.dsns.dev:10086` |
| Proxy | Traefik IngressRoutes | — | Routes to LAN backends via EndpointSlices |

---

## Repository Layout

```text
.
├── argocd/
│   ├── root-app.yaml          # Root Application — watches argocd/apps on main
│   └── apps/                  # One Application per infra component / app
│       ├── argocd-server-lb-app.yaml
│       ├── cert-manager-app.yaml
│       ├── cert-manager-config-app.yaml
│       ├── kube-vip-app.yaml
│       ├── traefik-app.yaml
│       ├── minecraft-app.yaml
│       ├── v2ray-app.yaml
│       └── web-proxy-app.yaml
├── infra/
│   ├── argocd-server-lb/      # LoadBalancer Service for argocd-server (.9)
│   ├── cert-manager/          # ClusterIssuer (LE prod / Cloudflare) + sealed token
│   ├── kube-vip/              # DaemonSet + RBAC (service-LB mode)
│   └── traefik/               # Helm values (replicas: 2, LB IP .10, redirect)
├── apps/
│   ├── minecraft/             # Velocity + Limbo deployments, services, sealed config
│   ├── v2ray/                 # Deployment + Service + sealed config
│   └── web-proxy/             # Namespace, IngressRoutes, Certificates, ext Services
└── talos/
    ├── controlplane-patch.yaml  # VIP .8, schedulable CP, unattended install
    └── nodes/
        ├── cp-01.yaml  # hostname: talos-m2
        ├── cp-02.yaml  # hostname: talos-m4
        └── cp-03.yaml  # hostname: talos-raider
```

Conventions:

- Sealed secrets: `*.sealed.yaml` (committed, safe) + `*.TEMPLATE.yaml` (field reference, never real values).
- `_talos/` (generated configs, `secrets.yaml`, `talosconfig`, `kubeconfig`) is local-only and git-ignored. Never commit it.

---

## Prerequisites

- `talosctl` (match Talos `v1.14.0`), `kubectl` (match K8s `v1.37.0`), `kubeseal`, `git`.
- 3 VMs (UTM × 2, Proxmox × 1) booted from the Talos ISO, on the same L2 as `10.3.3.0/24`, bridged networking.
- LAN DHCP (or static reservations) for `.9` / `.190` / `.192`; VIPs `.8`, `.9` (LB), `.10` free and outside the DHCP pool.
- Cloudflare API token (DNS-Edit scoped) for the `cert-manager` DNS-01 solver.
- Domains delegated to Cloudflare: `dsns.dev`, `seung.dev`, `mseung.dev`.

---

## Bootstrap

### 1. Clone

```bash
git clone https://github.com/dsnsgithub/homelab/
cd homelab
```

If a working cluster already exists, skip to [step 4](#4-install-argo-cd).

### 2. Generate Talos Config

```bash
talosctl gen config homelab https://10.3.3.8:6443 \
  --config-patch @talos/controlplane-patch.yaml \
  --output-dir _talos

# Persist for upgrades / new nodes — do not commit
talosctl gen secrets -o _talos/secrets.yaml \
  --from-controlplane-config _talos/controlplane.yaml
```

### 3. Apply Config & Bootstrap etcd

Replace `<node-1/2/3>` with the per-node IPs (`.9`, `.190`, `.192`). Add nodes by appending lines with matching `talos/nodes/cp-0N.yaml` hostname patches.

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

# Bootstrap etcd exactly once, on the first node
talosctl bootstrap -n <node-1>

# Kubeconfig via the HA VIP
talosctl kubeconfig -n 10.3.3.8
kubectl get nodes -A -o wide
```

Expect 3x `Ready` control-plane nodes. The API VIP `.8` may take ~30–60s to appear.

### 4. Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

> If bootstrapping onto k3s or similar, disable bundled ServiceLB/Traefik first — kube-vip + this repo's Traefik own `.9`/`.10`.

### 5. Install Sealed Secrets

```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
```

Install `kubeseal` locally. For every `*.TEMPLATE.yaml`, create the plain Secret locally, seal it against the cluster, and commit only the sealed output:

```bash
# example
kubectl create secret generic velocity-config -n minecraft \
  --from-file=velocity.toml=./velocity.toml \
  --from-file=forwarding.secret=./forwarding.secret \
  --dry-run=client -o yaml | kubeseal -o yaml > apps/minecraft/velocity-secret.sealed.yaml
```

Current sealed inputs: `infra/cert-manager/cloudflare-secret`, `apps/minecraft/velocity-secret`, `apps/v2ray/v2ray-config`.

### 6. Deploy the Root App

```bash
kubectl apply -f argocd/root-app.yaml
```

Argo CD syncs everything under `argocd/apps` (prune + selfHeal). Poll interval is ~3 minutes. Argo CD UI/API is at `https://10.3.3.9` (via the `argocd-server-lb` LoadBalancer).

---

## GitOps Workflow

1. Edit manifests in `infra/` or `apps/`, or add a new `argocd/apps/<name>-app.yaml`.
2. Push to `main`.
3. Argo CD auto-syncs within ~3 minutes. No `kubectl apply` needed.
4. Verify: `argocd app list` or the UI at `https://10.3.3.9`.

The Root App (`argocd/root-app.yaml`) is the only object applied by hand after bootstrap. Everything else is a child Application.

---

## Virtual IPs & Load Balancers

- `10.3.3.8` — Talos VIP for `kube-apiserver`. Defined in `talos/controlplane-patch.yaml` (`machine.network.interfaces[].vip.ip`). Do not manage via kube-vip (`cp_enable=false`).
- `10.3.3.9` — `argocd-server-lb` Service (`type: LoadBalancer`, `loadBalancerIP: 10.3.3.9`) in `infra/argocd-server-lb/`. Announced by kube-vip.
- `10.3.3.10` — Traefik Service (`infra/traefik/values.yaml`) + Minecraft proxy Service share this VIP. Announced by kube-vip.

Failover behavior: ARP announcement + gratuitous ARP on leader change. Test with `kubectl delete pod -n kube-system -l app.kubernetes.io/name=kube-vip-ds` on the leader and watch the VIP migrate.

---

## DNS & TLS

- Issuer: `letsencrypt-prod` (`infra/cert-manager/clusterissuer.yaml`), ACME `https://acme-v02.api.letsencrypt.org/directory`, Cloudflare DNS-01. Contact: `dominic@seung.dev`.
- Wildcard Certificates (`apps/web-proxy/certificates.yaml`):

| Secret | Domains |
|--------|---------|
| `dsns-wildcard-tls` | `dsns.dev`, `*.dsns.dev` |
| `mseung-wildcard-tls` | `mseung.dev`, `*.mseung.dev` |
| `seung-wildcard-tls` | `seung.dev`, `*.seung.dev` |

- IngressRoutes (`apps/web-proxy/ingressroutes.yaml`, all `websecure`):

| Host | Backend |
|------|---------|
| `*.mseung.dev` | `max-proxy:80` (LAN `10.3.3.218`) |
| `*.seung.dev` | `max-proxy:80` (LAN `10.3.3.218`) |
| `code.dsns.dev` | `code:7799` (LAN `10.3.3.195`) |
| `immich.dsns.dev` | `immich:2283` (LAN `10.3.3.172`) |
| `vray.dsns.dev` | `vray:10086` → `v2ray-service.v2ray-vpn` |

External LAN backends are wired as ClusterIP Services + manually managed EndpointSlices (static LAN IPs). If a backend moves, update `apps/web-proxy/services.yaml`.

---

## Applications

| App | Namespace | Status | Entry |
|-----|-----------|--------|-------|
| Minecraft Velocity + Limbo (`mc.dsns.dev`) | `minecraft` | ✅ Deployed (2 replicas, `itzg/mc-proxy:java25`, MC `26.2`, Velocity + Limbo handler + Simple Voice Chat) | `10.3.3.10:25577` TCP+UDP |
| Web Proxy (Traefik IngressRoutes) | `web-proxy` | ✅ Deployed | `10.3.3.10:443` |
| V2Ray VPN | `v2ray-vpn` | ✅ Deployed (2 replicas) | `vray.dsns.dev` |
| Immich | — | ⬜ Planned (`immich.dsns.dev` route + slice stub exists, backend at `.172`) | — |
| T3 Code (`code.dsns.dev`) | — | ⬜ Planned (route + slice stub exists, backend at `.195`) | — |
| WireGuard VPN | — | ⬜ Planned | — |

---

## Day-2 Operations

**Regenerate config after editing `talos/controlplane-patch.yaml`:**

```bash
talosctl gen config homelab https://10.3.3.8:6443 \
  --with-secrets _talos/secrets.yaml \
  --config-patch-control-plane @talos/controlplane-patch.yaml \
  --output-dir _talos
```

**Add a node (e.g. `cp-04`):**

1. Add `talos/nodes/cp-04.yaml` with the new hostname.
2. Regenerate (above), then:

```bash
talosctl apply-config --insecure -n <node-4> \
  --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-04.yaml
talosctl config endpoint <node-4>
talosctl config node <node-4>
```

3. Verify etcd health: `talosctl etcd status`.

**Upgrade Talos / Kubernetes:** bump versions, regenerate, then `talosctl upgrade -n <each-node> --image ghcr.io/siderolabs/installer:vX.Y.Z` one node at a time, waiting for `Ready` between nodes. Never upgrade two etcd members concurrently.

**Rotate Sealed Secrets cert / API tokens:** re-seal with current controller cert (`kubeseal --fetch-cert`) and re-apply via Git. Cloudflare token lives in `infra/cert-manager/cloudflare-secret.sealed.yaml`.

**Backups:** `etcd` is the source of truth (3-way replicated). Keep `_talos/secrets.yaml` + `talosconfig` offline. All cluster state beyond that is reconstructible from this repo + sealed secrets.

---

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `kubectl` cannot reach `10.3.3.8:6443` | `talosctl -n <node-ip> get addresses`, VIP present? All VMs bridged on same L2? |
| VIP `.9` / `.10` not responding | `kubectl -n kube-system get ds kube-vip-ds`, `kubectl -n kube-system logs ds/kube-vip-ds`, gratuitous ARP blocked by switch/AP isolation? |
| Argo CD out of sync | `argocd app list`, `kubectl -n argocd get app`, check `root-app.yaml` targetRevision/path |
| TLS not issuing | `kubectl -n web-proxy get cert`, `kubectl describe clusterissuer letsencrypt-prod`, Cloudflare token valid? `kubectl -n cert-manager logs deploy/cert-manager` |
| Sealed secret won't decrypt | Controller cert rotated? Re-seal: `kubeseal --fetch-cert > cert.pem` and re-generate |
| Mixed-arch scheduling issues | `kubectl describe pod` — image pull / exec format errors mean missing arm64/amd64 manifest; pin multi-arch tags |
| UTM VM loses network after reboot | Confirm bridged interface re-attached; Talos `deviceSelector: physical: true` picks the first physical NIC |

---

## Roadmap

- [x] HA Talos (3x control-plane, schedulable)
- [x] kube-vip service LB (`.9`, `.10`)
- [x] Argo CD Root App GitOps
- [x] cert-manager + Cloudflare wildcard TLS
- [x] Minecraft Velocity + Limbo
- [x] V2Ray VPN + web proxy routes
- [ ] Immich (`immich.dsns.dev`)
- [ ] T3 Code (`code.dsns.dev`)
- [ ] WireGuard VPN
- [ ] Persistent storage story (Longhorn / NFS — _TODO: confirm choice_)
- [ ] Backup verification + restore drill
- [ ] Monitoring (kube-prometheus-stack / alerting)

---

> **Open inputs needed to finalize:** per-VM vCPU/RAM/disk for `talos-m2`, `talos-m4`, `talos-raider`; host RAM/disk for both Mac minis; Raider host CPU/RAM/disk + whether Talos runs as Proxmox VM or bare metal; DHCP reservations vs static; storage backend choice for Immich/T3 Code.
