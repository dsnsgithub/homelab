# DSNS's Homelab: HA Talos Kubernetes with GitOps

This repository builds and operates my Kubernetes cluster. Argo CD installs/synchronizes everything above the OS from this repo to the cluster.

Anything that isn't colored in the diagram can be changed, as this homelab is platform agnostic. The architecture will continue to evolve as I migrate more applications.

## Architecture
<img width="800" alt="homelab" src="https://github.com/user-attachments/assets/26417614-4b7c-4b8f-9e7d-741b91777660" />


## Quickstart

Bootstrap is a one-time procedure. Afterwards, every change follows the same loop: edit, push, and Argo CD syncs automatically.

```bash
git clone https://github.com/dsnsgithub/homelab/ && cd homelab
# Assumes an existing Talos Kubernetes cluster. To start from scratch, see docs/bootstrap.md.
kubectl apply -f argocd/root-app.yaml
```

Open the Argo CD UI at `https://10.3.3.9`.

## Applications (currently migrating to the cluster)
In addition to kube-vip, all stateless applications (proxies, VPNs) are replicated across two different nodes to minimize downtime.

| | Service | Address | Status |
|--|---------|---------|--------|
| <img src="docs/assets/icons/minecraft.png" width="22" height="22" alt="Minecraft icon"> | Minecraft (Velocity proxy) | `mc.dsns.dev:25565` | Live |
| <img src="docs/assets/icons/v2ray.png" width="22" height="22" alt="V2Ray icon"> | V2Ray VPN | `vray.dsns.dev` | Live |
| <img src="docs/assets/icons/seung.ico" width="22" height="22" alt="seung.dev icon"> <img src="docs/assets/icons/mseung.ico" width="22" height="22" alt="mseung.dev icon"> | Web proxy (Traefik) | `*.seung.dev`, `*.mseung.dev` | Live |
| <img src="docs/assets/icons/immich.ico" width="22" height="22" alt="Immich icon"> | Immich | `immich.dsns.dev` | Planned |
| <img src="docs/assets/icons/code.ico" width="22" height="22" alt="T3 Code icon"> | T3 Code Web | `code.dsns.dev` | Planned |
| <img src="docs/assets/icons/wireguard.png" width="22" height="22" alt="WireGuard icon"> | WireGuard VPN | Not publicly accessible | Planned |

## Docs

| Page | Contents |
|------|----------|
| [Bootstrap](docs/bootstrap.md) | Prerequisites and first-time Talos to Argo CD bring-up |
| [Operations](docs/operations.md) | Day-to-day GitOps, growing the cluster, secrets |
| [Talos GitOps](docs/talos-gitops.md) | Self-hosted runner that auto-applies `talos/` commits |


