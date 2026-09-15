# Networking

Everything lives on the home network range `10.3.3.0/24` (about 250 usable addresses). Machines get their own addresses automatically from the router, while three special **shared addresses** are defined in this repo. A shared address always reaches a healthy machine: if its current holder fails, another machine claims it within seconds and tells the network "send it here now."

All virtual machines must use bridged networking (their own address on the home network). Private/NAT modes break the claiming mechanism.

## Shared Addresses

| Address | What lives there | Who moves it on failure |
|---------|------------------|-------------------------|
| `10.3.3.8` | Cluster control panel (`https://10.3.3.8:6443`) | Talos itself (built into the OS) |
| `10.3.3.9` | Argo CD website (ports 80 / 443) | kube-vip helper |
| `10.3.3.10` | Websites + Minecraft server | kube-vip helper |

In repo terms:

- `10.3.3.8` is set in `talos/controlplane-patch.yaml`. kube-vip is told to leave it alone (`cp_enable=false`).
- `10.3.3.9` comes from the `argocd-server-lb` entry (`type: LoadBalancer`) in `infra/argocd-server-lb/`. ("LoadBalancer" just means "give this service a network address.")
- `10.3.3.10` is requested by Traefik (`infra/traefik/values.yaml`) and shared with the Minecraft entry. Traefik runs 2 copies and sends all plain-HTTP visitors to HTTPS automatically.
- kube-vip (`v1.0.4`) is a helper installed on every machine. The machines hold a quick vote (5-second terms); the winner claims the shared addresses. You can watch it survive failure with `kubectl delete pod -n kube-system -l app.kubernetes.io/name=kube-vip-ds` on the current holder — the address reappears on another machine.

## Website Names & HTTPS Certificates

Certificates are free and renew by themselves. A free service (Let's Encrypt) issues them after this repo proves it owns the domain names by placing a code in their DNS settings (via Cloudflare). One "wildcard" certificate covers a domain plus all its subdomains (e.g. `*.dsns.dev`).

| Stored certificate | Covers |
|--------|---------|
| `dsns-wildcard-tls` | `dsns.dev` and everything under it |
| `mseung-wildcard-tls` | `mseung.dev` and everything under it |
| `seung-wildcard-tls` | `seung.dev` and everything under it |

Forwarding rules (in `apps/web-proxy/ingressroutes.yaml` — "which website goes where," all encrypted):

| Website | Sent to (computer on the home network) |
|------|---------|
| anything under `mseung.dev` | computer at `10.3.3.218`, port 80 |
| anything under `seung.dev` | computer at `10.3.3.218`, port 80 |
| `code.dsns.dev` | computer at `10.3.3.195`, port 7799 |
| `immich.dsns.dev` | computer at `10.3.3.172`, port 2283 |
| `vray.dsns.dev` | the in-cluster VPN app, port 10086 |

Computers outside the cluster are listed in a small address book in `apps/web-proxy/services.yaml`. If one of those computers ever changes address, that file is the one place to update.
