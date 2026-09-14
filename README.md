# DSNS's Homelab

Kubernetes GitOps repo for my homelab, managed by ArgoCD.

## Migration Checklist (currently in the process of migration)

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

### Deploy Homelab

1. Clone Homelab Repo
```bash
git clone https://github.com/dsnsgithub/homelab/
```

2. Install ArgoCD
```
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
Be sure to disable any preinstalled load balancers such as ServiceLB (if using k3s or similar) before deploying this repository.
   
4. Deploy repo
kubectl apply -f argocd/root-app.yaml
```

Argo CD will watch files in `argocd/apps/`, with any changes pushed to `main` will be synced within around 3 minutes.
