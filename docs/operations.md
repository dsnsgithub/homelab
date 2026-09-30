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
