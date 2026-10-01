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

MetalLB advertises `10.3.3.9–11` on the LAN. Services retain their existing `spec.loadBalancerIP` requests: Argo CD uses `.9`, Traefik `.10`, and Minecraft `.11`. Keep these IPs outside DHCP; `10.3.3.8` belongs to Talos's API VIP. Flannel and kube-proxy continue to provide cluster networking.

The `metallb` Argo CD application installs the chart and the pool/L2 advertisement in `infra/metallb/config`. The configuration syncs after the controller and speakers are healthy. BGP's FRR-K8s backend is disabled because this cluster uses L2 only. MetalLB honors the existing `node.kubernetes.io/exclude-from-external-load-balancers` label, so `talos-m2` does not announce Service IPs. Speakers need TCP and UDP port `7946` open between nodes.

### Replace kube-vip with MetalLB

First merge [the Application cleanup PR #37](https://github.com/dsnsgithub/homelab/pull/37) and let root sync it. This enables cascading deletion for the existing kube-vip Application.

Expect a brief Service interruption during the handover. Use Kubernetes directly at `10.3.3.8:6443`; the Argo CD UI's Service IP is being moved.

Before merging, pause root and kube-vip auto-sync, and wait for any in-progress syncs to finish:

```bash
kubectl -n argocd patch application root --type=merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
kubectl -n argocd patch application kube-vip --type=merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
```

After merging the MetalLB PR, delete the kube-vip Application and wait for its managed resources to be cleaned up before resuming root:

```bash
kubectl -n argocd delete application kube-vip --wait=true --timeout=3m
kubectl apply -f argocd/root-app.yaml
```

Once Argo CD has created the MetalLB resources, verify:

```bash
kubectl -n metallb-system rollout status deployment/metallb-controller --timeout=3m
kubectl -n metallb-system rollout status daemonset/metallb-speaker --timeout=3m
kubectl -n metallb-system get ipaddresspools,l2advertisements
kubectl get services -A
```

From another LAN machine, check Argo CD and Traefik HTTPS, Minecraft TCP, and voice-chat UDP. The cascading deletion also removes kube-vip's managed RBAC and ServiceAccount.

To roll back, pause root, delete the MetalLB Application with cascading cleanup, and wait for deletion to finish. Restore the previous repository revision and kube-vip Application before resuming root auto-sync.

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
