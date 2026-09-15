# Hardware

| Hostname | Host hardware | Virtualization | Talos VM allocation | Node IP | Arch | Role |
|----------|---------------|----------------|---------------------|---------|------|------|
| `talos-m2` | Mac mini (2023, base model: M2 8-core CPU / 10-core GPU, 8 GB unified memory, 256 GB SSD) + 2 TB SSD backing the VM | UTM, bridged networking | _TODO: vCPU / RAM / disk_ | `10.3.3.9` | arm64 | control-plane (schedulable) |
| `talos-m4` | Mac mini (2024, base model: M4 10-core CPU / 10-core GPU, 16 GB unified memory, 256 GB SSD) | UTM, bridged networking | _TODO: vCPU / RAM / disk_ | `10.3.3.190` | arm64* | control-plane (schedulable) |
| `talos-raider` | Raider (Proxmox node, borrowed from separate Proxmox cluster) — _TODO: CPU / RAM / disk_ | Proxmox VE VM, bridged networking | _TODO: vCPU / RAM / disk_ | `10.3.3.192` | amd64 | control-plane (schedulable) |

Notes:

- All three VMs use **bridged networking** so each Talos node gets a first-class LAN IP on `10.3.3.0/24` (required for ARP-based VIP failover).
- Mixed-arch cluster (arm64 + amd64) — all images must be multi-arch. Current images (`itzg/mc-proxy`, `v2fly/v2fly-core`, `busybox`, Traefik, cert-manager, kube-vip) all ship multi-arch manifests.
- `talos-m2` runs its UTM VM off the attached 2 TB SSD (host internal disk is the stock 256 GB SSD).
- `talos-raider` is borrowed from another Proxmox cluster. Losing it loses etcd quorum safety margin — replace before decommissioning (see [Operations](operations.md#add-a-node)).

> Still TODO: vCPU/RAM/disk per UTM VM, Raider host specs + Proxmox VM allocation (CPU type, RAM, disk size/type).
