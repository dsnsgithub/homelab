# Architecture

Three machines working as one computer. Each machine runs the same locked-down operating system and can run any app — there is no single boss machine, so any one of them can fail and everything keeps working. (The technical term for this setup is a 3-node cluster where every node is a schedulable control-plane; three is the smallest number that can safely take a vote when something disagrees.)

- **Locked-down operating system:** Talos Linux. There is no login screen or SSH — you manage it remotely with a tool called `talosctl`.
- **One shared address for control:** `10.3.3.8` always reaches a healthy machine's control panel (the Kubernetes API on port `6443`).
- **Address failover helper:** a small program called kube-vip runs on every machine and moves the other shared addresses (`.9`, `.10`) to a survivor if one fails. See [Networking](networking.md).
- **Autopilot:** Argo CD watches the `argocd/apps/` folder on the `main` branch and installs whatever it finds, cleaning up anything deleted and fixing anything changed by hand (within about 3 minutes). See [Operations](operations.md).
- **Front door:** Traefik runs two copies, forces encrypted connections (plain HTTP automatically redirects to HTTPS), and passes each visitor to the right app — including apps on other home computers.
- **Passwords in Git:** secret values are encrypted before committing, so the repository never contains a real password. Files ending in `.sealed.yaml` are safe to share; matching `.TEMPLATE.yaml` files show what fields to fill in.

```text
GitHub (main) ──► Argo CD Root App ──► Foundations + Apps
                                         ├── kube-vip (moves shared addresses on failure)
                                         ├── cert-manager (free HTTPS certificates)
                                         ├── Traefik (front door, 10.3.3.10)
                                         ├── Sealed Secrets (encrypted passwords in Git)
                                         ├── Minecraft (Velocity + Limbo, mc.dsns.dev)
                                         ├── V2Ray VPN (vray.dsns.dev)
                                         └── Web Proxy (forwards to other home computers)
```

This is what healthy looks like (exact output of `kubectl get nodes -A -o wide`):

```text
NAME           STATUS   ROLES           AGE    VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE          KERNEL-VERSION          CONTAINER-RUNTIME
talos-m2       Ready    control-plane   144m   v1.37.0   10.3.3.189     <none>        Talos (v1.14.0)   6.18.48-talos (arm64)   containerd://2.3.4
talos-m4       Ready    control-plane   143m   v1.37.0   10.3.3.190    <none>        Talos (v1.14.0)   6.18.48-talos (amd64*)  containerd://2.3.4
talos-raider   Ready    control-plane   143m   v1.37.0   10.3.3.192    <none>        Talos (v1.14.0)   6.18.48-talos (amd64)   containerd://2.3.4
```

All three say `Ready`, meaning they have joined and can take work.

> `talos-m4` shows `amd64` above but is expected `arm64` (Apple Silicon UTM guest). Verify with `kubectl get node talos-m4 -o jsonpath='{.status.nodeInfo.architecture}'`.

Normally manager machines refuse regular app work; this repo turns that refusal off (`talos/controlplane-patch.yaml`), so all three machines also run apps. That is deliberate for a small home setup.

## Software Stack

| Piece | Version | What it does |
|-------|---------|--------------|
| Talos Linux | `v1.14.0`, kernel `6.18.48-talos` | Operating system on every machine, managed remotely |
| Kubernetes | `v1.37.0` | Teamwork software that makes three machines act as one |
| containerd | `2.3.4` | Runs each app in its own isolated box (a container) |
| Talos built-in shared address | `10.3.3.8` | Always reaches a healthy machine's control panel |
| kube-vip | `v1.0.4` | Moves the `.9` / `.10` addresses to a healthy machine |
| Argo CD | `stable` release | Autopilot: installs whatever this repo describes |
| Traefik | installed by Argo CD, address `.10` | Front door: routes visitors, 2 copies for safety |
| cert-manager + Let's Encrypt | free certificates via Cloudflare | Issues and renews HTTPS certificates automatically |
| Sealed Secrets | controller + `kubeseal` tool | Keeps passwords encrypted inside Git |
| Velocity proxy (`itzg/mc-proxy:java25`) + Limbo | game version `26.2` | Minecraft server entry point, 2 copies, port 25577 |
| V2Ray (`v2fly/v2fly-core`) | 2 copies | Private tunnel (VPN), reached at `vray.dsns.dev` |
| Traefik forwarding rules | — | Sends each website to its home computer by address |

## Repository Layout

```text
.
├── argocd/
│   ├── root-app.yaml          # The one file applied by hand: tells Argo CD what to watch
│   └── apps/                  # One install instruction per foundation piece / app
├── infra/
│   ├── argocd-server-lb/      # Gives the Argo CD website its address (.9)
│   ├── cert-manager/          # Certificate settings + encrypted Cloudflare login
│   ├── kube-vip/              # The address-failover helper and its permissions
│   └── traefik/               # Front-door settings (2 copies, address .10, force HTTPS)
├── apps/
│   ├── minecraft/             # Minecraft server files + encrypted passwords
│   ├── v2ray/                 # VPN files + encrypted settings
│   └── web-proxy/             # Website forwarding rules + certificates
├── talos/
│   ├── controlplane-patch.yaml  # OS settings: shared address .8, run apps everywhere
│   └── nodes/                   # Each machine's name (cp-01..03)
└── docs/                      # This documentation
```

Two rules for the whole repo:

- Passwords: only `*.sealed.yaml` (encrypted, safe) gets committed. `*.TEMPLATE.yaml` files are blank forms showing what to fill in — never put real values in them.
- The `_talos/` folder (machine ID cards and logins generated during setup) lives only on your computer and is never committed to Git.
