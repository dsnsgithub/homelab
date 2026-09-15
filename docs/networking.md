# Networking

Subnet `10.3.3.0/24`. Nodes use DHCP with a static VIP layered on the physical interface (`talos/controlplane-patch.yaml`, `deviceSelector: physical: true`). All VMs are bridged — NAT/host-only breaks ARP failover.

## Virtual IPs

| Address | Purpose | Announced by |
|---------|---------|--------------|
| `10.3.3.8` | Kubernetes API (`https://10.3.3.8:6443`), Talos VIP | Talos built-in VIP |
| `10.3.3.9` | Argo CD Server LoadBalancer (HTTP 80 / HTTPS 443) | kube-vip DaemonSet (ARP) |
| `10.3.3.10` | Shared edge VIP: Traefik + Minecraft | kube-vip DaemonSet (ARP) |

- `10.3.3.8` is defined in `talos/controlplane-patch.yaml` (`machine.network.interfaces[].vip.ip`). Do not manage via kube-vip (`cp_enable=false`).
- `10.3.3.9` is the `argocd-server-lb` Service (`type: LoadBalancer`, `infra/argocd-server-lb/`).
- `10.3.3.10` is pinned by Traefik (`infra/traefik/values.yaml`, `loadBalancerIP`) and shared with the Minecraft proxy Service. Traefik runs 2 replicas with HTTP→HTTPS redirect (`web → websecure`).
- kube-vip (`ghcr.io/kube-vip/kube-vip:v1.0.4`) runs as a hostNetwork DaemonSet in `kube-system`, ARP mode, leader election (lease 5s / renew 3s / retry 1s). On leader loss a survivor sends gratuitous ARP and takes the VIP. Test with `kubectl delete pod -n kube-system -l app.kubernetes.io/name=kube-vip-ds` on the leader.

## DNS & TLS

- Issuer `letsencrypt-prod` (`infra/cert-manager/clusterissuer.yaml`): ACME prod, Cloudflare DNS-01, contact `dominic@seung.dev`.
- Wildcards (`apps/web-proxy/certificates.yaml`):

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

External LAN backends are ClusterIP Services + manually managed EndpointSlices with static LAN IPs. If a backend moves, update `apps/web-proxy/services.yaml`.
