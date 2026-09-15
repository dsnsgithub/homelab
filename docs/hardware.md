# Hardware

Three virtual machines on the home network, each acting as an equal member of the cluster. How to read the table: **Hostname** is the machine's name inside the cluster; **Virtualization** is the app that pretends to be a computer (UTM on the Macs, Proxmox on Raider); **Arch** is the chip family (`arm64` = Apple chips, `amd64` = regular PCs); **Role** is the same for all — every machine helps manage the cluster and runs apps.

| Hostname | Physical machine | Virtualization | Resources for the VM | Node address | Chip | Role |
|----------|------------------|----------------|----------------------|--------------|------|------|
| `talos-m2` | Mac mini (2023, base model: M2 chip, 8 GB memory, 256 GB SSD) + 2 TB SSD holding the VM | UTM, bridged networking | _TODO: CPUs / memory / disk_ | `10.3.3.189` | arm64 | manager + runs apps |
| `talos-m4` | Mac mini (2024, base model: M4 chip, 16 GB memory, 256 GB SSD) | UTM, bridged networking | _TODO: CPUs / memory / disk_ | `10.3.3.190` | arm64* | manager + runs apps |
| `talos-raider` | Raider (Proxmox server, borrowed from a separate Proxmox group) — _TODO: CPU / memory / disk_ | Proxmox VM, bridged networking | _TODO: CPUs / memory / disk_ | `10.3.3.192` | amd64 | manager + runs apps |

Things worth knowing:

- **Bridged networking** means each virtual machine appears as its own independent computer on the home network with its own address. This is required — without it, the shared addresses cannot move between machines on failure.
- **Two chip families** (Apple + regular PC) means every app used here must support both. All current apps do.
- `talos-m2` keeps its virtual machine on the attached 2 TB SSD; the Mac's own internal disk is the stock 256 GB one.
- `talos-raider` is borrowed. The cluster needs at least 2 of 3 machines agreeing to make decisions, so if Raider is ever taken back, set up a replacement first — see [Operations](operations.md#add-a-machine).

> Still TODO: CPUs/memory/disk given to each virtual machine, and Raider's physical specs plus its VM allocation (CPU type, memory, disk size/type).
