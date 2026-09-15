# Applications

| App | Namespace | Status | Entry |
|-----|-----------|--------|-------|
| Minecraft Velocity + Limbo (`mc.dsns.dev`) | `minecraft` | ✅ Deployed (2 replicas, `itzg/mc-proxy:java25`, MC `26.2`, Velocity + Limbo handler + Simple Voice Chat) | `10.3.3.10:25577` TCP+UDP |
| Web Proxy (Traefik IngressRoutes) | `web-proxy` | ✅ Deployed | `10.3.3.10:443` |
| V2Ray VPN | `v2ray-vpn` | ✅ Deployed (2 replicas) | `vray.dsns.dev` |
| Immich | — | ⬜ Planned (`immich.dsns.dev` route + slice stub exists, backend `.172`) | — |
| T3 Code (`code.dsns.dev`) | — | ⬜ Planned (route + slice stub exists, backend `.195`) | — |
| WireGuard VPN | — | ⬜ Planned | — |

## Details

- **Minecraft** (`apps/minecraft/`): Velocity proxy Deployment + Limbo backend, Services on the shared `.10` VIP, sealed `velocity-config`. TCP+UDP `25577` for gameplay + Simple Voice Chat.
- **V2Ray** (`apps/v2ray/`): `v2fly/v2fly-core` Deployment (2 replicas), sealed `config.json`, exposed via `vray.dsns.dev:10086` through Traefik.
- **Web Proxy** (`apps/web-proxy/`): namespace, wildcard `Certificate`s, `IngressRoute`s, and static Services + EndpointSlices pointing at LAN backends (`.218` max-proxy, `.195` code, `.172` immich). See [Networking](networking.md#dns--tls).
- **Planned:** Immich and T3 Code routes/slices already exist — only the LAN backends are pending. WireGuard has no manifests yet.

To add an app: create manifests under `apps/<name>/` plus an Argo CD Application in `argocd/apps/<name>-app.yaml`, push to `main`. See [Operations](operations.md#gitops-workflow).
