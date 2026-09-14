# DSNS's Homelab

Kubernetes GitOps repo for my homelab, managed by ArgoCD.

## Migration Checklist (currently a work in progress)

Virtual IPs (created by kube-vip): 
- `10.3.3.8` (k8s control-plane API)
- `10.3.3.9` (argocd LoadBalancer)
- `10.3.3.10` (Minecraft Proxy LoadBalancer)

Applications (run on a heterogeneous cluster of both arm64 and amd64):
- [x] Minecraft Proxy + Limbo Server
- [ ] Web Proxy
- [ ] Wireguard VPN
- [ ] V2Ray VPN
- [ ] Immich
- [ ] T3 Code

## Deploy Homelab onto existing Kubernetes cluster

1. Clone Homelab Repo
```bash
git clone https://github.com/dsnsgithub/homelab/
```

2. Install ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
Be sure to disable any preinstalled load balancers such as ServiceLB (if using k3s or similar) before deploying this repository.
   
3. Deploy repo
```bash
kubectl apply -f argocd/root-app.yaml
```

Argo CD will watch files in `argocd/apps/`, any changes pushed to `main` will be synced/deployed within around 3 minutes.
