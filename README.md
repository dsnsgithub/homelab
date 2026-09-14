# DSNS's Homelab

Kubernetes GitOps repo for my homelab, managed by ArgoCD.

## Migration Checklist (currently a work in progress)

Virtual IPs (created by kube-vip): 
- `10.3.3.8` (k8s control-plane API)
- `10.3.3.9` (argocd LoadBalancer)
- `10.3.3.10` (Minecraft Proxy LoadBalancer)
- `10.3.3.11` (V2Ray LoadBalancer)

kube-vip will elect a leader node to manage a virtual IP, auto detecting the interface to bind to.
kube-vip has been configured to advertise over ARP and if the leader node goes offline, a new leader will be elected and sends gratuitous ARP to claim the IP.

This configuration expects a minimum of three control plane nodes for quorum.

Applications:
- [x] Minecraft Proxy + Limbo Server
- [ ] Web Proxy
- [ ] Wireguard VPN
- [x] V2Ray VPN
- [ ] Immich
- [ ] T3 Code

## Environments

| Environment | Source | Where it runs |
|---|---|---|
| Production | `main` branch, `apps/*` + `infra/*` via Applications in `argocd/apps/` | Prod namespaces (`minecraft`, `v2ray-vpn`, `kube-system`, `argocd`) with pinned virtual IPs |
| Staging | Any other branch, `apps/*/overlays/staging` via the ApplicationSet in `argocd/apps/staging-branch-appset.yaml` | Ephemeral `staging-<app>-<branch>` namespaces, ClusterIP only, replicas=1, dummy secrets |

Only `apps/*` are staged. `infra/*` (kube-vip, argocd-server-lb) is cluster-singleton state (virtual IPs, `kube-system`) and is never staged. Staging can never steal a prod virtual IP: overlays drop `loadBalancerIP` and force `ClusterIP`, and CI enforces this (see below).

## Staging environments

Every non-`main` branch gets its own staging deployment automatically: the
`staging-branches` ApplicationSet creates one app per (app, branch), each
tracking its branch head — so every commit you push is synced to staging
within a few minutes. `main` is excluded (it is production).

Deleting a branch deletes its staging Application **and** its staged resources (`preserveResourcesOnDeletion: false`), so no manual cleanup.

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

Staging uses dummy secrets (`apps/*/overlays/staging/staging-secret.yaml`), not real credentials: SealedSecrets are strict-scoped to their prod namespace and cannot decrypt elsewhere. If a staging env needs real secrets, re-seal them for that namespace with `--scope namespace-wide`.

## Can ArgoCD sync this?

Every PR and every push to `main` runs `.github/workflows/argocd-preview.yaml`, which needs no cluster access:

1. `kustomize build` of each prod target and each staging overlay (exactly what ArgoCD renders).
2. `kubeconform -strict` schema validation of the rendered output.
3. Staging isolation checks (no `LoadBalancer`, no `loadBalancerIP`, no prod namespaces, no `SealedSecret`, replicas=1).
4. A base-vs-head diff stat plus the full rendered manifests as the `rendered-manifests` artifact.

Green checks mean ArgoCD should sync cleanly. For a live server-side diff against the real cluster, run locally:

```bash
argocd app diff minecraft --local apps/minecraft
argocd app diff v2ray --local apps/v2ray
```

## Deploy Homelab onto existing Kubernetes cluster

1. Clone Homelab Repository
```bash
git clone https://github.com/dsnsgithub/homelab/
```

2. Install ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
Be sure to disable any preinstalled load balancers such as ServiceLB (if using k3s or similar) before deploying this repository.

3. Install Sealed Secrets controller + kubeseal
```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
```

Install the `kubeseal` CLI locally.

4. Deploy Repository
```bash
kubectl apply -f argocd/root-app.yaml
```

Argo CD will watch files in `argocd/apps/`, any changes pushed to `main` will be synced/deployed within around 3 minutes.
