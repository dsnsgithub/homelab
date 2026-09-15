# Applications

What runs on the cluster today, and what is planned. "2 copies" means the app runs twice so one copy can fail without anyone noticing.

| App | What it is | Status | How to reach it |
|-----|-----------|--------|-------|
| Minecraft Velocity + Limbo | Game server entry point (with voice chat) | Live, 2 copies, game version `26.2` | `10.3.3.10:25577` |
| Web Proxy | Front-door rules forwarding websites to home computers | Live | `10.3.3.10:443` |
| V2Ray VPN | Private tunnel for secure browsing | Live, 2 copies | `vray.dsns.dev` |
| Immich | Photo library (forwarding rule ready, computer at `.172` pending) | Planned | `immich.dsns.dev` |
| T3 Code | Coding tool (forwarding rule ready, computer at `.195` pending) | Planned | `code.dsns.dev` |
| WireGuard VPN | Simpler private tunnel | Planned, not built yet | — |

## Details

- **Minecraft** (`apps/minecraft/`): two parts — Velocity greets connecting players, Limbo holds them before a game server is attached. Shares the `.10` address; game + voice traffic on port `25577` (both TCP and UDP). Passwords are stored locked (`velocity-config`).
- **V2Ray** (`apps/v2ray/`): the VPN program, 2 copies, settings stored locked (`config.json`). Reached through the front door at `vray.dsns.dev`, port 10086.
- **Web Proxy** (`apps/web-proxy/`): the forwarding rules, the HTTPS certificates, and the address book of home computers (`.218` general proxy, `.195` coding tool, `.172` photos). See [Networking](networking.md#website-names--https-certificates).
- **Planned:** Immich and T3 Code only wait on their home computers — the forwarding rules already exist. WireGuard has no files yet.

## Adding an App

1. Put the app's files in a new folder under `apps/<name>/`.
2. Add one install instruction in `argocd/apps/<name>-app.yaml` so the autopilot picks it up.
3. Push to `main`. Argo CD installs it within a few minutes — see [Operations](operations.md#everyday-changes).

If the app needs a password, fill in its `*.TEMPLATE.yaml` form, lock it with `kubeseal`, and commit only the locked file (see [Bootstrap](bootstrap.md#5-install-the-password-locker)).
