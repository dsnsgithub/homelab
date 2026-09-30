# Operations

## Control Plane Scheduling

`talos-m2` uses the default control plane taint (`node-role.kubernetes.io/control-plane:NoSchedule`) and is excluded from external load balancers. `talos-m4` and `talos-raider` remain control plane nodes with those defaults removed so they can run workloads.

Apply Talos configuration changes with:

```bash
topf --topfconfig talos/topf.yaml apply
```

## Drain and Undrain a Node

Drain:
```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

Undrain:
```bash
kubectl uncordon <node-name>
```

## Repair a Crashlooping etcd Member

https://docs.siderolabs.com/talos/v1.14/build-and-extend-talos/cluster-operations-and-maintenance/disaster-recovery#prepare-control-plane-nodes

```bash
talosctl -n <IP> reset --graceful=false --reboot --system-labels-to-wipe=EPHEMERAL
```
