# Hardware

| Hostname | Host | Virtualization | VM allocation | Node IP | Arch | Role |
|----------|------|----------------|---------------|---------|------|------|
| `talos-m2` | Mac mini 2023, base spec (M2 8c CPU / 10c GPU, 8 GB unified, 256 GB SSD) with a 2 TB SSD holding the VM | UTM, bridged | _TODO: vCPU / RAM / disk_ | `10.3.3.189` | arm64 | control-plane (schedulable) |
| `talos-m4` | Mac mini 2024, base spec (M4 10c CPU / 10c GPU, 16 GB unified, 256 GB SSD) | UTM, bridged | _TODO: vCPU / RAM / disk_ | `10.3.3.190` | arm64* | control-plane (schedulable) |
| `talos-raider` | Raider Proxmox node, borrowed from a separate cluster (host CPU / RAM / disk: still to be recorded) | Proxmox VE VM, bridged | _TODO: vCPU / RAM / disk_ | `10.3.3.192` | amd64 | control-plane (schedulable) |

Notes:

- **Bridged networking** is configured on all three VMs, so each node gets its own LAN address on `10.3.3.0/24`. Bridging is required because ARP-based VIP failover only works when all nodes share L2 adjacency. NAT or host-only networking breaks it.
- **Mixed arch** (arm64 and amd64) means every image must ship a multi-arch manifest. The current images (`itzg/mc-proxy`, `v2fly/v2fly-core`, `busybox`, Traefik, cert-manager, kube-vip) all qualify, so watch for `exec format` pod errors when adding new ones.
- `talos-m2` keeps its VM on the attached 2 TB SSD. The host internal disk is the stock 256 GB drive.
- `talos-raider` is borrowed from another Proxmox cluster. etcd tolerates the loss of one member, so reclaiming Raider without a replacement would remove all quorum redundancy. Add a successor first (see [Operations](operations.md#add-a-node)).

Still to be recorded: vCPU, RAM, and disk for each VM, plus the Raider host specs and VM allocation (CPU type, RAM, and disk size and type).
