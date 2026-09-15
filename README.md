# DSNS's Homelab: HA Talos Kubernetes with GitOps

This repository builds and operates a home Kubernetes cluster. Three Talos nodes form a single HA cluster, and Argo CD installs and synchronizes everything above the OS. Readers who understand Kubernetes concepts but have not bootstrapped a cluster should start with [Architecture](docs/architecture.md), then follow [Bootstrap](docs/bootstrap.md) to build it.

## How It Works

- **Cluster:** three Talos nodes form a single HA cluster. Every node is a control-plane member and is schedulable, so the cluster has no dedicated workers. The failure of any single node does not take the cluster down.
- **Talos Linux** is the OS on each node. It is minimal and immutable, provides no SSH access, and is managed remotely with `talosctl`.
- **Argo CD** is the GitOps autopilot. It watches `argocd/apps/` on `main` and converges the cluster to whatever is committed (auto-sync with prune and selfHeal, with a poll interval around 3 minutes).
- **Traefik** is the ingress controller. It terminates TLS, redirects HTTP to HTTPS, and routes each hostname to the correct Service, including Services that point at other machines on the LAN.
- **cert-manager with Let's Encrypt** issues and renews wildcard certificates through Cloudflare DNS-01. **Sealed Secrets** keeps secret values encrypted in Git.

## Docs

| Page | Contents |
|------|----------|
| [Architecture](docs/architecture.md) | Design, software stack, repo layout |
| [Hardware](docs/hardware.md) | Node inventory (M2/UTM, M4/UTM, Raider/Proxmox) |
| [Networking](docs/networking.md) | VIPs (.8/.9/.10), kube-vip failover, DNS and TLS |
| [Bootstrap](docs/bootstrap.md) | Prerequisites and first-time Talos to Argo CD bring-up |
| [Applications](docs/applications.md) | Minecraft, V2Ray, web proxy, planned apps |
| [Operations](docs/operations.md) | Day-to-day GitOps, growing the cluster, troubleshooting, roadmap |

## At a Glance

### Nodes

Every node is a control-plane member, every node is schedulable, and all nodes are bridged on `10.3.3.0/24`.

| Node | Host | IP |
|------|------|----|
| `talos-m2` | M2 Mac mini / UTM | `10.3.3.189` |
| `talos-m4` | M4 Mac mini / UTM | `10.3.3.190` |
| `talos-raider` | Proxmox VM (borrowed) | `10.3.3.192` |

See [Hardware](docs/hardware.md) for the full inventory.

### Virtual IPs

A VIP (virtual IP) is a shared address that floats to a healthy node on failure.

| IP | Purpose |
|----|---------|
| `10.3.3.8` | Kubernetes API (Talos VIP) |
| `10.3.3.9` | Argo CD (kube-vip) |
| `10.3.3.10` | Traefik and Minecraft (kube-vip) |

See [Networking](docs/networking.md) for failover details.

### Stack

The stack combines Talos `v1.14.0`, Kubernetes `v1.37.0`, kube-vip `v1.0.4` (ARP failover for Service LB IPs), Traefik (ingress), cert-manager (Let's Encrypt through Cloudflare DNS-01), and Sealed Secrets (encrypted secrets in Git). The full version table is in [Architecture](docs/architecture.md).

### Apps

- [x] Minecraft Velocity and Limbo is live at `mc.dsns.dev` (`10.3.3.10:25577`).
- [x] V2Ray VPN is live at `vray.dsns.dev`.
- [x] The web proxy is live at `10.3.3.10:443` (Traefik IngressRoutes).
- [ ] Immich is planned for `immich.dsns.dev`.
- [ ] T3 Code is planned for `code.dsns.dev`.
- [ ] WireGuard VPN is planned.

See [Applications](docs/applications.md) for details.

## Quickstart

Bootstrap is a one-time procedure. Afterwards, every change follows the same loop: edit, push, and Argo CD syncs automatically.

```bash
git clone https://github.com/dsnsgithub/homelab/ && cd homelab
# Assumes an existing Talos Kubernetes cluster. For first-time bring-up, see docs/bootstrap.md.
kubectl apply -f argocd/root-app.yaml   # Root App syncs everything else within about 3 minutes
```

Open the Argo CD UI at `https://10.3.3.9`.

## Layout

```text
argocd/   # Root App and one Application per component
infra/    # kube-vip, traefik, cert-manager, argocd-server-lb
apps/     # minecraft, v2ray, web-proxy
talos/    # controlplane patch and per-node hostname patches
docs/     # detailed documentation
```

Read the documentation in this order: [Architecture](docs/architecture.md), [Hardware](docs/hardware.md), [Networking](docs/networking.md), then [Bootstrap](docs/bootstrap.md).
