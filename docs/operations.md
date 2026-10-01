# Operations

## PR Previews

Add the `preview` label to a PR to deploy each opted-in chart into
`<chart>-pr-<number>`. The ApplicationSet discovers
`charts/*/values-preview.yaml` at the PR commit and loads that file over the
chart's normal `values.yaml`. Production applications continue to use their
normal values.

To enable previews for a new application chart:

1. Add `charts/<chart>/values-preview.yaml` with its preview overrides. Use `{}`
   if the defaults are already suitable for previews.
2. Ensure every namespaced resource uses `.Values.namespace`. The ApplicationSet
   supplies the PR namespace with higher precedence than the preview values file.
3. Disable or replace production hostnames, fixed LoadBalancer IPs, shared storage,
   and production backend connections as appropriate for the application.

Charts without `values-preview.yaml` are skipped. Keep cluster infrastructure
charts out of previews. This opt-in configures preview behavior; it does not
enforce isolation from production. Minecraft still uses the configured lobby
backend, and web-proxy Services still reference the configured upstreams.

Minecraft previews use ClusterIP. Connect to `localhost:25565` after running:

```bash
kubectl -n minecraft-pr-32 port-forward service/mc-proxy-service 25565:25565
```

Replace `32` with the PR number. Port forwarding supports TCP only, so UDP voice
chat requires access from inside the cluster. Older PRs must include the preview
values files to be discovered and the configurable Minecraft Service type to
avoid claiming the production VIP.

## Control Plane Scheduling

`talos-m2` uses the default control plane taint (`node-role.kubernetes.io/control-plane:NoSchedule`) and is excluded from external load balancers. `talos-m4` and `talos-raider` remain control plane nodes with those defaults removed so they can run workloads.

Apply Talos configuration changes with:

```bash
topf --topfconfig talos/topf.yaml apply
```

## Service Load Balancers

Cilium allocates and announces the Service addresses in `infra/cilium/config/load-balancer-pool.yaml`. The pool and L2 policy select Services with the label `homelab.dsns.dev/load-balancer: cilium`. Services request a fixed address with the `lbipam.cilium.io/ips` annotation; the local chart values still call that setting `loadBalancerIP`.

| Service | Reserved IP |
|---------|-------------|
| Argo CD | `10.3.3.9` |
| Traefik | `10.3.3.10` |
| Minecraft (TCP and UDP) | `10.3.3.11` |

Keep these addresses outside DHCP. When adding an address, extend the pool and the excluded `/32` entries in both `talos/control-plane/01-vip.yaml` and `talos/control-plane/02-node.yaml`, then apply the Talos patches. Keep `10.3.3.8` out of the pool: it belongs to Talos's API VIP.

The Cilium agent runs on every node, including `talos-m2`, but the L2 policy excludes nodes carrying `node.kubernetes.io/exclude-from-external-load-balancers`. Currently only `talos-m4` and `talos-raider` announce Service IPs. Each Service has one announcing node, with lease-based failover; this does not distribute incoming traffic across both nodes before it reaches the cluster.

Use `externalTrafficPolicy: Cluster` for these Services. [Cilium L2 announcements](https://docs.cilium.io/en/stable/network/l2-announcements/) is currently beta and does not support `externalTrafficPolicy: Local`.

Inspect allocations, leases, and detected LAN interfaces:

```bash
kubectl get ciliumloadbalancerippools,ciliuml2announcementpolicies
kubectl get services -A -l homelab.dsns.dev/load-balancer=cilium -o wide
kubectl -n kube-system get leases
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --verbose
kubectl -n kube-system exec ds/cilium -- cilium-dbg shell -- db/show devices
```

The L2 leases start with `cilium-l2announce-`. Verify `10.3.3.9–11` are reachable from another machine on the LAN. On nodes with multiple NICs, ensure Cilium selects the interface on `10.3.3.0/24`; configure the Helm `devices` option and the policy's `interfaces` regexes if automatic detection selects the wrong NIC.

For an existing Flannel/kube-vip cluster, use the [migration procedure](cilium-migration.md) before applying the new Talos patch or syncing the Cilium applications.

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
