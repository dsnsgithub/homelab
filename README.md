# DSNS's Homelab — HA Talos Kubernetes with GitOps

3-node HA Talos cluster on mixed arm64/amd64 hardware, fully managed as code with Argo CD. Bootstrap once by hand, then everything flows through Git.

## Docs

| Page | Contents |
|------|----------|
| [Architecture](docs/architecture.md) | Design, software stack, repo layout |
| [Hardware](docs/hardware.md) | Node inventory (M2/UTM, M4/UTM, Raider/Proxmox) |
| [Networking](docs/networking.md) | VIPs (.8/.9/.10), kube-vip, DNS & TLS |
| [Bootstrap](docs/bootstrap.md) | Prerequisites + Talos → Argo CD bring-up |
| [Applications](docs/applications.md) | Minecraft, V2Ray, web proxy, planned apps |
| [Operations](docs/operations.md) | GitOps flow, Day-2 ops, troubleshooting, roadmap |

## At a Glance

### Nodes

All control-plane, all schedulable, bridged on `10.3.3.0/24`.

| Node | Host | IP |
|------|------|----|
| `talos-m2` | M2 Mac mini / UTM | `10.3.3.9` |
| `talos-m4` | M4 Mac mini / UTM | `10.3.3.190` |
| `talos-raider` | Proxmox VM (borrowed) | `10.3.3.192` |

Details in [Hardware](docs/hardware.md).

### Virtual IPs

| IP | Purpose |
|----|---------|
| `10.3.3.8` | Kubernetes API (Talos VIP) |
| `10.3.3.9` | Argo CD |
| `10.3.3.10` | Traefik + Minecraft (kube-vip) |

Details in [Networking](docs/networking.md).

### Stack

Talos `v1.14.0`, Kubernetes `v1.37.0`, kube-vip `v1.0.4`, Traefik, cert-manager (Let's Encrypt + Cloudflare), Sealed Secrets. Full table in [Architecture](docs/architecture.md).

### Apps

Live: Minecraft Velocity + Limbo, V2Ray, Web proxy. Planned: Immich, T3 Code, WireGuard. See [Applications](docs/applications.md).

## Quickstart

```bash
git clone https://github.com/dsnsgithub/homelab/ && cd homelab
# Full bring-up: docs/bootstrap.md
talosctl kubeconfig -n 10.3.3.8
kubectl get nodes -A -o wide
kubectl apply -f argocd/root-app.yaml   # Root App syncs the rest (~3 min)
```

Argo CD UI: `https://10.3.3.9`.

## Layout

```text
argocd/   # Root App + one Application per component
infra/    # kube-vip, traefik, cert-manager, argocd-server-lb
apps/     # minecraft, v2ray, web-proxy
talos/    # controlplane patch + per-node hostname patches
docs/     # detailed documentation
```

See [Architecture](docs/architecture.md#repository-layout) for the annotated tree and [Operations](docs/operations.md#gitops-workflow) for the GitOps flow.
