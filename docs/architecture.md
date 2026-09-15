# Architecture

3-node HA Talos cluster. All nodes are control-plane and schedulable — no dedicated workers. This keeps a small homelab quorum-safe (3 members for etcd) while still running workloads.

- **Immutable OS:** Talos Linux, no SSH. All management via `talosctl` API.
- **HA API:** Talos built-in VIP `10.3.3.8` fronts `kube-apiserver:6443`.
- **Service LB:** kube-vip DaemonSet in service mode (`svc_enable=true`, `cp_enable=false`). Only announces LoadBalancer Services (`.9`, `.10`). See [Networking](networking.md).
- **GitOps:** Argo CD Root App watches `argocd/apps/` on `main`, auto-sync with prune + selfHeal (~3 min poll). See [Operations](operations.md).
- **Edge:** Traefik (2 replicas) terminates TLS, enforces HTTP→HTTPS, routes to in-cluster services and LAN backends via Services + EndpointSlices.
- **Secrets:** Bitnami Sealed Secrets. Only `*.sealed.yaml` is committed; `*.TEMPLATE.yaml` documents shape.

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

Live state at time of writing:

```text
NAME           STATUS   ROLES           AGE    VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE          KERNEL-VERSION          CONTAINER-RUNTIME
talos-m2       Ready    control-plane   144m   v1.37.0   10.3.3.9      <none>        Talos (v1.14.0)   6.18.48-talos (arm64)   containerd://2.3.4
talos-m4       Ready    control-plane   143m   v1.37.0   10.3.3.190    <none>        Talos (v1.14.0)   6.18.48-talos (amd64*)  containerd://2.3.4
talos-raider   Ready    control-plane   143m   v1.37.0   10.3.3.192    <none>        Talos (v1.14.0)   6.18.48-talos (amd64)   containerd://2.3.4
```

> `talos-m4` shows `amd64` above but is expected `arm64` (Apple Silicon UTM guest). Verify with `kubectl get node talos-m4 -o jsonpath='{.status.nodeInfo.architecture}'`.

Taints for `node-role.kubernetes.io/control-plane` are removed in `talos/controlplane-patch.yaml` so pods schedule on all three nodes.

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

## Repository Layout

```text
.
├── argocd/
│   ├── root-app.yaml          # Root Application — watches argocd/apps on main
│   └── apps/                  # One Application per infra component / app
├── infra/
│   ├── argocd-server-lb/      # LoadBalancer Service for argocd-server (.9)
│   ├── cert-manager/          # ClusterIssuer (LE prod / Cloudflare) + sealed token
│   ├── kube-vip/              # DaemonSet + RBAC (service-LB mode)
│   └── traefik/               # Helm values (replicas: 2, LB IP .10, redirect)
├── apps/
│   ├── minecraft/             # Velocity + Limbo deployments, services, sealed config
│   ├── v2ray/                 # Deployment + Service + sealed config
│   └── web-proxy/             # Namespace, IngressRoutes, Certificates, ext Services
├── talos/
│   ├── controlplane-patch.yaml  # VIP .8, schedulable CP, unattended install
│   └── nodes/                   # Per-node hostname patches (cp-01..03)
└── docs/                      # This documentation
```

Conventions:

- Sealed secrets: `*.sealed.yaml` (committed, safe) + `*.TEMPLATE.yaml` (field reference, never real values).
- `_talos/` (generated configs, `secrets.yaml`, `talosconfig`, `kubeconfig`) is local-only and git-ignored. Never commit it.
