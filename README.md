# DSNS's Homelab

Kubernetes GitOps repo for my homelab, managed by ArgoCD.

## Migration Checklist (currently in the process of migration)

Virtual IP: 10.3.3.8 (created by kube-vip)

Applications (run on a heterogenous cluster of both arm64 and amd64):
- [x] Minecraft Proxy + Limbo Server
- [ ] Web Proxy
- [ ] VPN Services
-  [ ] T3 Code

### Bootstrap ArgoCD with the root app

```bash
kubectl apply -f argocd/root-app.yaml
```

This root application will watch files in `argocd/apps/`, which launches the applications.

Any changes pushed to `main` will be synced automatically.