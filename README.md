# DSNS's Homelab

Kubernetes GitOps repo for my homelab, managed by ArgoCD.

## Migration Checklist (currently a work in progress)

Virtual IPs (created by kube-vip): 
- `10.3.3.8` (k8s control-plane API)
- `10.3.3.9` (argocd LoadBalancer)
- `10.3.3.10` (Minecraft Proxy LoadBalancer)
- `10.3.3.11` (V2Ray LoadBalancer)
- `10.3.3.12` (Traefik web proxy LoadBalancer)

kube-vip will elect a leader node to manage a virtual IP, auto detecting the interface to bind to.
kube-vip has been configured to advertise over ARP and if the leader node goes offline, a new leader will be elected and sends gratuitous ARP to claim the IP.

This configuration expects a minimum of three control plane nodes for quorum.

Applications:
- [x] Minecraft Proxy + Limbo Server
- [x] Web Proxy
- [ ] Wireguard VPN
- [x] V2Ray VPN
- [ ] Immich
- [ ] T3 Code

## Deploy Homelab onto existing Kubernetes cluster

1. Clone Homelab Repository
```bash
git clone https://github.com/dsnsgithub/homelab/
cd homelab
```

2. Install ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
Be sure to disable any preinstalled load balancers and proxies such as ServiceLB and Traefik (if using k3s or similar) before deploying this repository.

3. Install Sealed Secrets controller + kubeseal
```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
```

Install the `kubeseal` CLI locally. Find files with `*.TEMPLATE.yaml` and generate the required secret.

4. Deploy Repository
```bash
kubectl apply -f argocd/root-app.yaml
```

Argo CD will watch files in `argocd/apps/`, any changes pushed to `main` will be synced/deployed within around 3 minutes.
