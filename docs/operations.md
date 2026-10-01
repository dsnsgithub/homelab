# Operations

## Web Ingress

F5 NGINX Ingress Controller runs two replicas at `10.3.3.10`. Settings are in
`infra/nginx-ingress/values.yaml`: HTTP/2, reusable upstream connections,
permanent HTTPS redirects, streaming responses, and unrestricted uploads.
The header map preserves WebSocket upgrades without closing ordinary HTTP
upstream connections. See the [controller documentation](https://docs.nginx.com/nginx-ingress-controller/).

`web-proxy` owns the wildcard, Code, and Immich Ingresses and certificates.
V2Ray owns its Ingress beside `v2ray-service` in `v2ray-vpn` because this
controller requires NGINX Plus for ExternalName backends. cert-manager issues
`vray-dsns-tls` there through `letsencrypt-prod`; the web certificates stay
unchanged. Production Ingresses and certificates are disabled in PR previews.

### Cut Over from Traefik

Plan a maintenance window for the first migration. The old Traefik Application
has no resource deletion finalizer, so pruning that Application alone leaves
its controller and LoadBalancer Service running. Retire it with a cascading
delete before NGINX claims the same VIP.

Before merging the migration, pause automatic sync for the affected apps:

```bash
argocd app set root --sync-policy none
argocd app set traefik --sync-policy none
argocd app set web-proxy --sync-policy none
argocd app set v2ray --sync-policy none
```

After the migration is on `main`, delete Traefik and confirm its Service and
Deployment are gone, then sync the root app. This restores the child apps'
automatic sync policies from Git and installs NGINX:

```bash
argocd app delete traefik --cascade --yes
kubectl -n traefik get services,deployments
# Continue once the old Service and Deployment have been deleted.
argocd app sync root
argocd app set root --sync-policy automated --auto-prune --self-heal
argocd app wait nginx-ingress web-proxy v2ray --sync --health --timeout 300
kubectl -n v2ray-vpn wait --for=condition=Ready certificate/vray-dsns-tls --timeout=300s
kubectl -n nginx-ingress get services,pods
kubectl -n web-proxy get ingress,certificates
kubectl -n v2ray-vpn get ingress,certificates
```

Verify HTTPS redirects, both wildcard domains, Code streaming, Immich uploads,
and a V2Ray connection to `/dsns`. Measure performance on the cluster.

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
