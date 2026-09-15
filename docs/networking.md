# Networking

The cluster lives on subnet `10.3.3.0/24`. Nodes receive their addresses through DHCP. Each VIP (a virtual IP, which is a shared address that floats to a healthy node) is layered onto the physical NIC in `talos/controlplane-patch.yaml` (`deviceSelector: physical: true`). All VMs use bridged networking, because NAT or host-only networking breaks ARP failover.

## Virtual IPs

| Address | Purpose | Announced by |
|---------|---------|--------------|
| `10.3.3.8` | Kubernetes API (`https://10.3.3.8:6443`), Talos VIP | Talos built-in VIP |
| `10.3.3.9` | Argo CD Server LoadBalancer (HTTP 80 / HTTPS 443) | kube-vip DaemonSet (ARP leader election) |
| `10.3.3.10` | Shared edge VIP: Traefik and Minecraft | kube-vip DaemonSet (ARP leader election) |

The repository defines each address as follows. `10.3.3.8` is set in `talos/controlplane-patch.yaml` (`machine.network.interfaces[].vip.ip`), and kube-vip is explicitly told to ignore control-plane VIPs (`cp_enable=false`). `10.3.3.9` is the `argocd-server-lb` Service (`type: LoadBalancer`, `loadBalancerIP: 10.3.3.9`) in `infra/argocd-server-lb/`. `10.3.3.10` is pinned by Traefik (`infra/traefik/values.yaml`, `loadBalancerIP`) and shared with the Minecraft proxy Service. Traefik runs 2 replicas with an HTTP to HTTPS redirect (`web` to `websecure`).

kube-vip (`ghcr.io/kube-vip/kube-vip:v1.0.4`) runs as a hostNetwork DaemonSet in `kube-system`. Nodes elect a leader on short terms (5s lease, 3s renew, 1s retry), the leader announces the Service IPs over ARP, and a newly elected leader reclaims them with gratuitous ARP after a failure. You can exercise failover by deleting the leader pod with `kubectl delete pod -n kube-system -l app.kubernetes.io/name=kube-vip-ds` and watching the VIP migrate.

## DNS and TLS

The `letsencrypt-prod` issuer (`infra/cert-manager/clusterissuer.yaml`) uses the production ACME server with a Cloudflare DNS-01 challenge, which proves domain ownership through a DNS TXT record. Its contact address is `dominic@seung.dev`.

Wildcard certificates are defined in `apps/web-proxy/certificates.yaml`. Each certificate covers one apex domain plus its wildcard subdomain:

| Secret | Domains |
|--------|---------|
| `dsns-wildcard-tls` | `dsns.dev`, `*.dsns.dev` |
| `mseung-wildcard-tls` | `mseung.dev`, `*.mseung.dev` |
| `seung-wildcard-tls` | `seung.dev`, `*.seung.dev` |

IngressRoutes are defined in `apps/web-proxy/ingressroutes.yaml` and all serve the `websecure` entrypoint. Each route maps a hostname to a backend:

| Host | Backend |
|------|---------|
| `*.mseung.dev` | `max-proxy:80` (LAN `10.3.3.218`) |
| `*.seung.dev` | `max-proxy:80` (LAN `10.3.3.218`) |
| `code.dsns.dev` | `code:7799` (LAN `10.3.3.195`) |
| `immich.dsns.dev` | `immich:2283` (LAN `10.3.3.172`) |
| `vray.dsns.dev` | `vray:10086`, forwarded to `v2ray-service.v2ray-vpn` (in-cluster) |

LAN backends outside the cluster are wired as ClusterIP Services with hand-managed EndpointSlices (static IP endpoints, for example `10.3.3.218`). If a backend moves, update `apps/web-proxy/services.yaml`. The IngressRoutes do not need to change.
