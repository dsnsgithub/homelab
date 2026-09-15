# DSNS's Homelab — HA Talos Kubernetes with GitOps

This repository sets up and runs my home servers. Instead of installing apps on one computer by hand, three small virtual computers team up to run everything, watch this repository for changes, and update themselves automatically.

## How It Works (30-Second Version)

- **Three virtual machines act as one computer.** This teamwork software is called Kubernetes. If one machine goes down, the other two keep everything running.
- **Talos is the operating system** on each machine — tiny, locked down, and identical everywhere, so there is nothing to configure by hand.
- **Argo CD is the autopilot.** It watches this repository on GitHub and installs whatever is described here. To change something, edit a file, push it, and the cluster catches up within a few minutes.
- **Traefik is the front door.** It receives web traffic and passes it to the right app, with encryption (HTTPS) handled automatically.
- **Web addresses and certificates are automatic.** Domain names and HTTPS certificates renew themselves (via Cloudflare and Let's Encrypt), so there is nothing to renew by hand.

## Docs

| Page | Contents |
|------|----------|
| [Architecture](docs/architecture.md) | Design, software stack, repo layout |
| [Hardware](docs/hardware.md) | Node inventory (M2/UTM, M4/UTM, Raider/Proxmox) |
| [Networking](docs/networking.md) | Shared addresses (.8/.9/.10), failover, DNS and certificates |
| [Bootstrap](docs/bootstrap.md) | Prerequisites + first-time setup, step by step |
| [Applications](docs/applications.md) | Minecraft, V2Ray, web proxy, planned apps |
| [Operations](docs/operations.md) | Everyday changes, growing the cluster, troubleshooting, roadmap |

## At a Glance

### Computers (called "nodes")

Three virtual machines on the home network `10.3.3.0/24`. Each one can run any app — there are no special workers.

| Node | Physical machine | Address |
|------|------------------|---------|
| `talos-m2` | M2 Mac mini / UTM | `10.3.3.189` |
| `talos-m4` | M4 Mac mini / UTM | `10.3.3.190` |
| `talos-raider` | Proxmox VM (borrowed) | `10.3.3.192` |

Details in [Hardware](docs/hardware.md).

### Shared Addresses (called "virtual IPs")

Each address below is shared: if the machine holding it fails, another one picks it up automatically within seconds.

| Address | What lives there |
|---------|------------------|
| `10.3.3.8` | Cluster control panel (the Kubernetes API) |
| `10.3.3.9` | Argo CD web interface |
| `10.3.3.10` | Websites and the Minecraft server |

Details in [Networking](docs/networking.md).

### Building Blocks

| Piece | What it does |
|-------|--------------|
| Talos `v1.14.0` | Operating system on every node |
| Kubernetes `v1.37.0` | Makes the three machines act as one |
| kube-vip `v1.0.4` | Moves shared addresses to a healthy machine |
| Traefik | Front door: routes visitors to the right app |
| cert-manager + Let's Encrypt | Issues and renews HTTPS certificates |
| Sealed Secrets | Stores passwords safely inside Git |

Full version table in [Architecture](docs/architecture.md).

### Apps

- [x] Minecraft Velocity + Limbo — `mc.dsns.dev` (`10.3.3.10:25577`)
- [x] V2Ray VPN — `vray.dsns.dev`
- [x] Web proxy (Traefik routes) — `10.3.3.10:443`
- [ ] Immich — `immich.dsns.dev` (planned)
- [ ] T3 Code — `code.dsns.dev` (planned)
- [ ] WireGuard VPN (planned)

See [Applications](docs/applications.md) for details.

## Quickstart

You only do the full setup once. Afterwards, every change is just "edit, push, done" — the cluster syncs itself.

```bash
git clone https://github.com/dsnsgithub/homelab/ && cd homelab
# Full first-time setup, step by step: docs/bootstrap.md
talosctl kubeconfig -n 10.3.3.8
kubectl get nodes -A -o wide
kubectl apply -f argocd/root-app.yaml   # Argo CD installs everything else (~3 min)
```

Argo CD web interface: `https://10.3.3.9`.

## Layout

```text
argocd/   # Tells Argo CD what to install (one file per piece)
infra/    # Shared foundations: address failover, front door, certificates
apps/     # The actual apps: minecraft, v2ray, web-proxy
talos/    # Operating-system settings + each machine's name
docs/     # Detailed documentation
```

New here? Read the pages in order: [Architecture](docs/architecture.md), [Hardware](docs/hardware.md), [Networking](docs/networking.md), then [Bootstrap](docs/bootstrap.md) when ready to build.
