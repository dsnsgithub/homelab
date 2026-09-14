# DSNS's Homelab

Kubernetes GitOps repo for my homelab, managed by ArgoCD.

Declarative bottom to top: OS + Kubernetes come from Talos configs generated
out of `bootstrap/talos/` (see [bootstrap/talos/README.md](bootstrap/talos/README.md)
for the bare-metal rebuild runbook) — this repo is the source of truth from
the machine patches all the way up to workloads.

## Migration Checklist (currently a work in progress)

Virtual IPs (created by kube-vip): 
- `10.3.3.8` (k8s control-plane API)
- `10.3.3.9` (argocd LoadBalancer)
- `10.3.3.10` (Minecraft Proxy LoadBalancer)
- `10.3.3.11` (V2Ray LoadBalancer)

kube-vip will elect a leader node to manage a virtual IP, auto detecting the interface to bind to.
kube-vip has been configured to advertise over ARP and if the leader node goes offline, a new leader will be elected and sends gratuitous ARP to claim the IP.

This configuration expects a minimum of three control plane nodes for quorum.

Applications (all Helm charts in `charts/`, deployed by ArgoCD):
- [x] Minecraft Proxy + Limbo Server (`charts/minecraft`)
- [ ] Web Proxy
- [ ] Wireguard VPN
- [x] V2Ray VPN (`charts/v2ray`)
- [ ] Immich
- [ ] T3 Code

Chart conventions (deliberate — keeps one chart serving every environment):

- Templates never pin a namespace (it comes from the release / ArgoCD
  destination) and contain **no environment branches** — only generic knobs
  (`replicaCount`, `service.type`, images) plus `with` guards for genuinely
  optional fields like `loadBalancerIP`.
- `values.yaml` holds neutral, staging-safe defaults (ClusterIP, no pinned
  IPs). Environment specifics live in the Application specs as inline
  `helm.values` — e.g. prod's `10.3.3.10` pin sits in `minecraft-app.yaml`
  next to its destination namespace, not in the chart.
- Credentials are separate charts, not conditionals: `*-secrets` charts hold
  the prod SealedSecrets (own Applications, prod namespaces only), and
  `staging-secrets` holds the dummy credentials every staging namespace gets.
- Render locally with `helm template <name> charts/<name> [--namespace X]`.

## Environments

| Environment | Source | Where it runs |
|---|---|---|
| Production | `main` branch, `charts/*` via Applications in `argocd/apps/` (env input in each app's `helm.values`) | Prod namespaces (`minecraft`, `v2ray-vpn`, `kube-system`, `argocd`) with pinned virtual IPs |
| Staging | Any other branch, same charts + shared inline `helm.values` via the ApplicationSet in `argocd/apps/staging-branch-appset.yaml` | One shared `staging-<branch>` namespace per branch, ClusterIP only, replicas=1, dummy secrets |

Only the app charts (`minecraft`, `v2ray`) are staged. Infra charts (kube-vip, argocd-server-lb, argocd-notifications) are cluster-singleton state and are never staged. Staging can never steal a prod virtual IP: chart defaults carry no `loadBalancerIP`, only prod app specs inject one — and CI enforces this (see below).

## Staging environments

Every non-`main` branch gets its own staging deployment automatically: the
`staging-branches` ApplicationSet creates three apps per branch —
`staging-minecraft-<branch>`, `staging-v2ray-<branch>`, `staging-secrets-<branch>` —
all tracking the branch head inside one shared `staging-<branch>` namespace.
Every commit you push is synced within a few minutes. `main` is excluded
(it is production).

Deleting a branch deletes its staging Applications **and** their staged resources (`preserveResourcesOnDeletion: false`), so no manual cleanup.

Setup (one time — without this, staging generators error and nothing is staged; prod is unaffected):

```bash
kubectl -n argocd create secret generic github-token \
  --from-literal=token=ghp_YOUR_TOKEN
```

Token scopes (repo is public): classic PAT with `public_repo`, or fine-grained PAT on `dsnsgithub/homelab` with Contents: read. See `argocd/github-token.TEMPLATE.yaml`.

Branch naming constraint: names must slug to a DNS-1123 label — short, lowercase, hyphenated (e.g. `feature/cool-thing`). Long names are truncated.

Verify staging is working:

```bash
kubectl -n argocd get applicationsets
kubectl -n argocd get applications -l homelab.dsns.dev/env=staging
kubectl get namespaces | grep staging
```

Staging uses dummy secrets (`charts/staging-secrets`, same names as prod), not real credentials: SealedSecrets are strict-scoped to their prod namespace and cannot decrypt elsewhere. If a staging env needs real secrets, re-seal them for that namespace with `--scope namespace-wide`.

## Can ArgoCD sync this?

Every PR and every push to `main` runs `.github/workflows/argocd-preview.yaml`, which needs no cluster access:

1. `helm lint` plus `helm template` of each chart — rendered from the Application specs themselves (same chart, namespace, and inline `helm.values` ArgoCD uses), for prod apps and the staging set (Helm v3.22.0 pinned — matches ArgoCD's renderer).
2. `kubeconform -strict` schema validation of the rendered output.
3. Staging isolation checks (no `LoadBalancer`, no `loadBalancerIP`, no prod namespaces, no `SealedSecret`, replicas=1).
4. A base-vs-head diff stat plus the full rendered manifests as the `rendered-manifests` artifact.

Green checks mean ArgoCD should sync cleanly. For a live server-side diff against the real cluster, run locally:

```bash
argocd app diff minecraft --local charts/minecraft
argocd app diff v2ray --local charts/v2ray
```

## Instant refresh via GitHub webhook (pull, but fast)

Sync stays pull-based, but pushes don't have to wait out the ~3 minute poll:
a GitHub push webhook hits ArgoCD's `/api/webhook` and refreshes affected
apps immediately.

```bash
ARGOCD_HOST=argocd.example.com ./bootstrap/configure-github-webhook.sh
```

The script stores a webhook secret in `argocd-secret`, restarts the server,
and prints the GitHub repo Settings → Webhooks values (payload URL
`https://$ARGOCD_HOST/api/webhook`, push events only). Prereq: github.com
must reach that URL — port-forward to the `10.3.3.9` LoadBalancer or a
tunnel — and with ArgoCD's self-signed TLS, disable SSL verification on the
webhook (or front it with a real cert). Delivery health is visible in the
webhook's "Recent Deliveries" on GitHub.

## GitHub sync statuses (outbound)

Every app — prod and staging — reports its live sync progress back to GitHub as commit statuses (`pending` while syncing, `success`/`failure` after), via the in-cluster ArgoCD notifications controller. The status is posted against the commit being synced: for staging that's the branch-head commit, so progress shows up directly on the PR. Fully outbound (the cluster calls `api.github.com`); GitHub never talks inbound, so nothing is exposed.

Setup (one time, after merging):

```bash
cp charts/argocd-notifications/github-pat.TEMPLATE.yaml \
   charts/argocd-notifications/github-pat.plain.yaml
# edit github-pat.plain.yaml, replace REPLACE_ME_GITHUB_PAT
kubectl apply -f charts/argocd-notifications/github-pat.plain.yaml
```

`github-pat.plain.yaml` is gitignored — the token can never be committed. Classic PAT needs `repo:status` (or `public_repo`); fine-grained needs Commit statuses: Read and write. One PAT can serve both this and the `github-token` branch-discovery secret if it has both scopes.

Verify:

```bash
# controller ships with ArgoCD, just confirm it's running
kubectl -n argocd get deploy argocd-notifications-controller
# after the next sync of any app, statuses appear on the commit in GitHub
kubectl -n argocd logs deploy/argocd-notifications-controller | grep -i github
```

Notes:

- The controller records what it sent in `notified.notifications.argoproj.io/*` annotations. Prod apps carry an `ignoreDifferences` rule for those so the root app doesn't see phantom drift.
- `charts/argocd-notifications` manages only the ConfigMap; the PAT Secret is applied manually and never pruned.
- Taking ownership of `argocd-notifications-cm` via GitOps is intentional. Re-applying the upstream ArgoCD install manifest would reset it — just re-sync the `argocd-notifications` app afterwards.

## Deploy Homelab onto existing Kubernetes cluster

1. Clone Homelab Repository
```bash
git clone https://github.com/dsnsgithub/homelab/
```

2. Install ArgoCD (pinned — see `bootstrap/versions.env`)
```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.2/manifests/install.yaml
```
Be sure to disable any preinstalled load balancers such as ServiceLB (if using k3s or similar) before deploying this repository.

3. Install Sealed Secrets controller + kubeseal
```bash
kubectl apply -f https://github.com/bitnami/sealed-secrets/releases/download/v0.39.1/controller.yaml
```

Install the `kubeseal` CLI locally.

4. Deploy Repository
```bash
kubectl apply -f argocd/root-app.yaml
```

Argo CD will watch files in `argocd/apps/` — pushes to `main` refresh apps instantly if the GitHub webhook is configured (see above), otherwise on the ~3 minute poll interval.
