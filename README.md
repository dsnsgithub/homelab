# DSNS's Homelab

Kubernetes GitOps repo for my homelab, managed by ArgoCD.

## Migration Checklist (currently in the process of migration)

Virtual IPs (created by kube-vip): 
- `10.3.3.8` (k8s control-plane API)
- `10.3.3.9` (argocd LoadBalancer)
- `10.3.3.10` (Minecraft Proxy LoadBalancer)

Applications (run on a heterogenous cluster of both arm64 and amd64):
- [x] Minecraft Proxy + Limbo Server
- [ ] Web Proxy
- [ ] Wireguard VPN
- [ ] V2Ray VPN
- [ ] Immich
- [ ] T3 Code

### Bootstrap ArgoCD with the root app

```bash
kubectl apply -f argocd/root-app.yaml
```

This root application will watch files in `argocd/apps/`, which launches the applications.

Any changes pushed to `main` will be synced automatically.
