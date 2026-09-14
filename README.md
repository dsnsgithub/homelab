# DSNS's Homelab

GitOps repo for my homelab, managed by ArgoCD.

## Structure

```
infra/kube-vip/        # kube-vip DaemonSet (control-plane VIP: 10.3.3.8)
apps/minecraft/         # Velocity proxy + Limbo + LoadBalancer service
argocd/apps/            # ArgoCD Application definitions (one per component)
argocd/root-app.yaml     # app-of-apps: apply this once, it manages the rest
```

### Bootstrap ArgoCD with the root app
```bash
kubectl apply -f argocd/root-app.yaml
```