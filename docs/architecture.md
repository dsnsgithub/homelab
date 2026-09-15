# Architecture

<p align="center">
  <img width="800" alt="Homelab architecture diagram mapping physical hosts to Talos virtual machines to the shared Kubernetes control plane, with Talos and kube-vip virtual IPs facing the public internet" src="https://github.com/user-attachments/assets/753e09ed-d8ef-4cce-a2bc-2b3f5bdeec63" />
</p>

This is a 3-node HA Talos cluster where every node is a control-plane member and schedulable, so there are no dedicated workers. The `control-plane` taint is removed in `talos/controlplane-patch.yaml` so pods schedule on all three nodes. Three members is the minimum for etcd quorum. etcd is the cluster's consistent datastore and it needs a majority (2 of 3) to accept writes, so any single node can fail without losing the cluster.

- **OS:** Talos Linux is minimal and immutable and provides no SSH access. All management goes through the `talosctl` API, for example `talosctl -n <node-ip> get addresses`.
- **API HA:** the Talos built-in VIP `10.3.3.8` fronts `kube-apiserver:6443`, so `kubectl` keeps working through any single-node failure.
- **Service LB:** the kube-vip DaemonSet (one pod per node) runs in service mode (`svc_enable=true`, `cp_enable=false`). It assigns the `.9` and `.10` LoadBalancer IPs and announces them over ARP, then re-announces them with gratuitous ARP on leader change. See [Networking](networking.md).
- **GitOps:** the Argo CD Root App watches `argocd/apps/` on `main` and auto-syncs with prune and selfHeal on a poll interval around 3 minutes. Deleted files therefore delete cluster objects, and manually edited objects are reverted. See [Operations](operations.md).
- **Edge:** Traefik runs 2 replicas. It terminates TLS, redirects `web` to `websecure`, and routes to in-cluster Services plus external LAN backends through headless Services and manually managed EndpointSlices (static Service to IP mappings for machines outside the cluster).
- **Secrets:** Bitnami Sealed Secrets encrypts secret values with the cluster key before they are committed. Only `*.sealed.yaml` files are committed, and each matching `*.TEMPLATE.yaml` file shows the expected fields with placeholder values.

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

The cluster looked like this at the time of writing (output of `kubectl get nodes -A -o wide`):

```text
NAME           STATUS   ROLES           AGE    VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE          KERNEL-VERSION          CONTAINER-RUNTIME
talos-m2       Ready    control-plane   144m   v1.37.0   10.3.3.189     <none>        Talos (v1.14.0)   6.18.48-talos (arm64)   containerd://2.3.4
talos-m4       Ready    control-plane   143m   v1.37.0   10.3.3.190    <none>        Talos (v1.14.0)   6.18.48-talos (amd64*)  containerd://2.3.4
talos-raider   Ready    control-plane   143m   v1.37.0   10.3.3.192    <none>        Talos (v1.14.0)   6.18.48-talos (amd64)   containerd://2.3.4
```

All three nodes report `Ready`.

> `talos-m4` reports `amd64` above but should be `arm64` (Apple Silicon UTM guest). Verify with `kubectl get node talos-m4 -o jsonpath='{.status.nodeInfo.architecture}'`.

## Software Stack

| Layer | Component | Version / source | Notes |
|-------|-----------|------------------|-------|
| OS | Talos Linux | `v1.14.0`, kernel `6.18.48-talos` | Immutable, API-driven |
| Kubernetes | kube-apiserver / kubelet | `v1.37.0` | etcd quorum across 3 control-plane nodes |
| Runtime | containerd | `2.3.4` | Container runtime on every node |
| Cluster VIP | Talos built-in VIP | `10.3.3.8` | API high availability |
| Service LB | kube-vip | `v1.0.4` | ARP announcements, service mode only |
| GitOps | Argo CD | `stable` manifest | Root App auto-sync, prune and selfHeal |
| Ingress | Traefik | Helm via Argo CD, `values.yaml` pins `.10` | 2 replicas |
| TLS | cert-manager and Let's Encrypt prod | DNS-01 via Cloudflare | Wildcard certs, auto-renew |
| Secrets | Bitnami Sealed Secrets | `controller.yaml` (latest) and `kubeseal` CLI | Encrypted in Git |
| Game | Velocity proxy (`itzg/mc-proxy:java25`) and Limbo | MC `26.2` | 2 replicas, TCP 25565 and UDP 25577 |
| VPN | V2Ray (`v2fly/v2fly-core`) | 2 replicas | `vray.dsns.dev:10086` |
| Proxy | Traefik IngressRoutes | Defined in-repo | Hostname to Service routing, including LAN backends |

Rows marked "Defined in-repo" have no upstream version because they are configured in this repository.

## Repository Layout

```text
.
├── argocd/
│   ├── root-app.yaml          # Root Application: watches argocd/apps on main
│   └── apps/                  # One Application per infra component / app
├── infra/
│   ├── argocd-server-lb/      # LoadBalancer Service for argocd-server (.9)
│   ├── cert-manager/          # ClusterIssuer (LE prod / Cloudflare) and sealed token
│   ├── kube-vip/              # DaemonSet and RBAC (service-LB mode)
│   └── traefik/               # Helm values (replicas: 2, LB IP .10, redirect)
├── apps/
│   ├── minecraft/             # Velocity and Limbo deployments, services, sealed config
│   ├── v2ray/                 # Deployment and Service and sealed config
│   └── web-proxy/             # Namespace, IngressRoutes, Certificates, ext Services
├── talos/
│   ├── controlplane-patch.yaml  # VIP .8, schedulable control-plane, unattended install
│   └── nodes/                   # Per-node hostname patches (cp-01..03)
└── docs/                      # Guides and icon assets
```

Two rules apply across the whole repo. **Passwords:** only `*.sealed.yaml` files are committed, because only the cluster can decrypt them. Each `*.TEMPLATE.yaml` file documents the expected fields with placeholder values and never holds real values. **Local credentials:** the `_talos/` folder holds generated machine configs, `secrets.yaml`, `talosconfig`, and `kubeconfig`. It is git-ignored and must never be committed, because it contains cluster credentials.
