# Operations

## Drain and Undrain a Node

Do one node at a time. All nodes run etcd, so losing two at once breaks quorum.

1. Map the Talos IP to the Kubernetes node name and confirm the cluster is healthy:

```bash
kubectl get nodes -o wide
talosctl etcd status -n <node-1>,<node-2>,<node-3>
```

2. Drain the node. `kubectl` takes the node name, not the IP:

```bash
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

3. Perform the maintenance, e.g.:

```bash
talosctl reboot -n <node-ip>
```

4. Wait for `Ready`, then undrain:

```bash
kubectl get nodes -o wide
kubectl uncordon <node-name>
```

Verify with `kubectl get nodes -o wide` (node is `Ready,SchedulingDisabled` while drained, `Ready` after uncordon) and `talosctl etcd status`. Pods do not move back automatically; they rebalance over time as new pods are scheduled.

Tip: `talosctl reboot -n <node-ip> --drain` cordons, drains, waits for `Ready`, and uncordons in one step. `talosctl upgrade` drains by default. Prefer the manual `kubectl drain` above when you want to inspect workload placement before rebooting.

## Repair a Crashlooping etcd Member

When `talosctl etcd status -n <node-1>,<node-2>,<node-3>`
returns only 2 of 3 rows, and `talosctl -n <failed-node> logs etcd` loops on
`service[etcd](Waiting): Error running Containerd(etcd)` with a raft panic:

```bash
talosctl etcd members -n <healthy-node>
talosctl etcd status -n <node-1>,<node-2>,<node-3>

talosctl -n <healthy-node> etcd remove-member <failed-member-id>
talosctl -n <failed-node> reset --graceful=false --reboot --system-labels-to-wipe=EPHEMERAL
```

Wait for the reboot, then verify it rejoins via the control-plane endpoint:

```bash
talosctl -n <node-1>,<node-2>,<node-3> etcd members
talosctl -n <node-1>,<node-2>,<node-3> etcd status
kubectl get nodes -o wide
```

## Storage (Piraeus)

Replicated block storage comes from Piraeus Operator v2 (LINSTOR/DRBD), synced by Argo CD before workloads: `piraeus-operator` (wave `-2`), then `piraeus-datastore` (wave `-1`) which creates the `LinstorCluster`, a thin `pool1` pool (`/var/lib/piraeus-datastore/pool1` on each node), and the `piraeus-storage` StorageClass (2 replicas). Claim it with `storageClassName: piraeus-storage`, as `apps/t3-code/pvc.yaml` does.

```bash
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor storage-pool list
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor resource list-volumes
```

New nodes pick up the pool automatically once they run the same Talos schematic (with the `siderolabs/drbd` extension) and machine config. Volumes survive single-node loss via the second replica; back up volume contents before a full-cluster reset.
