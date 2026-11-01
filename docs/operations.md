# Operations

## Making Changes

`main` is production. Open a PR for every change; `main` requires two checks
before merging:

- `validate` renders every Argo CD Application and preview chart the way Argo CD
  does, schema-checks the output with kubeconform, and validates the Talos
  machine configs. Run it locally with `.github/scripts/validate.sh`.
- `preview` deploys app charts into `<chart>-pr-<number>` namespaces when the PR
  changes a chart with `values-preview.yaml`, waits until they're Synced and
  Healthy at the PR's commit, and comments the result on the PR. PRs that don't
  touch those charts pass immediately. Infrastructure charts (Traefik,
  kube-vip, cert-manager) don't get previews; `validate` is their gate.

After merging, the `deploy` job (GitHub environment `production`):

1. Applies Talos machine configs with `topf` if `talos/` changed, one node at a
   time, stopping at the first node that doesn't stabilize. Run the workflow
   manually with `talos` checked to force an apply.
2. Tells Argo CD to refresh immediately, then streams each Application's sync and
   health until all of them are Synced and Healthy at the merged commit. The job
   fails if a sync fails, an Application stays Degraded for a minute, or 15
   minutes pass. The job summary shows the final state of every Application.

Argo CD still pulls `main` on its own, so a broken change that reaches `main`
through an admin bypass is applied anyway. Rolling updates keep the old pods
serving until replacements are ready; revert the PR to roll back.

### CI Credentials

The workflow joins the home LAN through WireGuard. Each environment holds:

| Secret | Environments | Contents |
|---|---|---|
| `WG_CONFIG` | `production`, `preview` | WireGuard peer config for CI. `AllowedIPs` and `DNS` are overridden to route only `10.3.3.0/24`. |
| `KUBECONFIG` | `production`, `preview` | Token for the `github-ci` ServiceAccount (`charts/github-ci`), which can only read Argo CD Applications and request refreshes. |
| `SOPS_AGE_KEY` | `production` | CI's age key for `talos/secrets.yaml`. topf derives Talos admin credentials from the decrypted bundle, so this key is full node access. |

`production` only accepts deployments from `main`, and fork PRs never run the
`preview` job, so PR branches can't read `SOPS_AGE_KEY`.

To rotate the CI age key, generate one with `age-keygen`, replace the CI
recipient in `.sops.yaml`, run `sops updatekeys talos/secrets.yaml`, and update
the secret with `gh secret set SOPS_AGE_KEY --env production`. To rotate the
Kubernetes token, delete the `github-ci-token` Secret in `argocd`, let Argo CD
recreate it, and rebuild the kubeconfig from its `token` and `ca.crt`.

## PR Previews

The `preview` job adds the `preview` label to PRs from this repository's
branches; the ApplicationSet only deploys labeled PRs, so fork PRs can't deploy
to the cluster. It deploys each opted-in chart into `<chart>-pr-<number>` using
`charts/*/values-preview.yaml` at the PR commit, loaded over the chart's normal
`values.yaml`. Production applications continue to use their normal values.
Closing or merging the PR deletes the previews, including their namespaces.

Previews run in the `previews` Argo CD project, which only allows resources in
`*-pr-*` namespaces and Namespaces named `*-pr-*`. `validate` also fails if a
preview renders resources outside its namespace, a LoadBalancer Service, or an
IngressRoute.

To enable previews for a new application chart:

1. Add `charts/<chart>/values-preview.yaml` with its preview overrides. Use `{}`
   if the defaults are already suitable for previews.
2. Ensure every namespaced resource uses `.Values.namespace`, and the chart
   renders its own Namespace when `createNamespace` is true. The ApplicationSet
   supplies the PR namespace with higher precedence than the preview values file.
3. Disable or replace production hostnames, fixed LoadBalancer IPs, shared storage,
   and production backend connections as appropriate for the application.

Charts without `values-preview.yaml` are skipped. Keep cluster infrastructure
charts out of previews. Previews are not network-isolated from production:
Minecraft still uses the configured lobby backend, and web-proxy Services still
reference the configured upstreams.

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

Talos configuration changes are applied by the `deploy` job after merging. To
apply by hand:

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
