# DSNS's Homelab: HA Talos Kubernetes with GitOps

This repository builds and operates my Kubernetes cluster. Argo CD installs/synchronizes everything above the OS from this repo to the cluster.

Anything that isn't colored in the diagram can be changed, as this homelab is platform agnostic. The architecture will continue to evolve as I migrate more applications.

## Architecture
<img width="800" alt="homelab" src="https://github.com/user-attachments/assets/25a4e163-f85c-4305-9ed4-04bc50ed634f" />


## Quickstart

Bootstrap is a one-time procedure. Afterwards, every change follows the same loop: edit, push, and Argo CD syncs automatically.

```bash
git clone https://github.com/dsnsgithub/homelab/ && cd homelab
# Assumes a Talos cluster with Cilium installed. See docs/bootstrap.md for setup.
kubectl apply -f argocd/root-app.yaml
```

Open the Argo CD UI at `https://10.3.3.9`.

## Applications (currently migrating to the cluster)
Cilium provides pod networking, replaces kube-proxy, and advertises Service IPs on the LAN using L2 announcements. The reserved Service IPs are `10.3.3.9–11`; Talos manages the Kubernetes API VIP at `10.3.3.8`. All stateless applications (proxies, VPNs) are replicated across two different nodes to minimize downtime.

Existing kube-vip clusters require a maintenance window; follow the [Cilium migration](docs/cilium-migration.md) before enabling the new GitOps applications.

| | Service | Address | Status |
|--|---------|---------|--------|
| <img src="docs/assets/icons/minecraft.png" width="22" height="22" alt="Minecraft icon"> | Minecraft (Velocity proxy) | `mc.dsns.dev:25565` | Live |
| <img src="docs/assets/icons/v2ray.png" width="22" height="22" alt="V2Ray icon"> | V2Ray VPN | `vray.dsns.dev` | Live |
| <img src="docs/assets/icons/seung.ico" width="22" height="22" alt="seung.dev icon"> <img src="docs/assets/icons/mseung.ico" width="22" height="22" alt="mseung.dev icon"> | Web proxy (Traefik) | `*.seung.dev`, `*.mseung.dev` | Live |
| <img src="docs/assets/icons/immich.ico" width="22" height="22" alt="Immich icon"> | Immich | `immich.dsns.dev` | Migration Planned |
| <img src="docs/assets/icons/code.ico" width="22" height="22" alt="T3 Code icon"> | T3 Code Web | `code.dsns.dev` | Migration Planned |
| <img src="docs/assets/icons/wireguard.png" width="22" height="22" alt="WireGuard icon"> | WireGuard VPN | Not publicly accessible | Potential Migration Planned |

## Docs

| Page | Contents |
|------|----------|
| [Bootstrap](docs/bootstrap.md) | Prerequisites and first-time Talos to Argo CD bring-up |
| [Operations](docs/operations.md) | Day-to-day GitOps, growing the cluster, secrets |
| [Cilium migration](docs/cilium-migration.md) | Replace Flannel, kube-proxy, and kube-vip on an existing cluster |
