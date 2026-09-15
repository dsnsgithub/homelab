# DSNS's Homelab: HA Talos Kubernetes with GitOps

This repository builds and operates my Kubernetes cluster, with Argo CD installing and synchronizing everything above the OS. Anything that isn't colored in the diagram can be changed, as this homelab is platform agnostic.

The architecture will continue to evolve as I migrate more applications.

## Architecture

<p align="center">
  <img width="800" alt="Homelab architecture diagram mapping physical hosts to Talos virtual machines to the shared Kubernetes control plane, with Talos and kube-vip virtual IPs facing the public internet" src="https://github.com/user-attachments/assets/753e09ed-d8ef-4cce-a2bc-2b3f5bdeec63" />
</p>

## Quickstart

Bootstrap is a one-time procedure. Afterwards, every change follows the same loop: edit, push, and Argo CD syncs automatically.

```bash
git clone https://github.com/dsnsgithub/homelab/ && cd homelab
# Assumes an existing Talos Kubernetes cluster. For first-time bring-up, see docs/bootstrap.md.
kubectl apply -f argocd/root-app.yaml   # Root App syncs everything else within about 3 minutes
```

Open the Argo CD UI at `https://10.3.3.9`.

## Applications (currently migrating to the cluster)

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


