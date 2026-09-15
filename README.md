# DSNS's Homelab

Kubernetes GitOps repo for my homelab, managed by ArgoCD.


<img width="1497" height="1118" alt="homelab" src="https://github.com/user-attachments/assets/753e09ed-d8ef-4cce-a2bc-2b3f5bdeec63" />

kube-vip will elect a leader node to manage a virtual IP, auto detecting the interface to bind to.
kube-vip has been configured to advertise over ARP and if the leader node goes offline, a new leader will be elected and sends gratuitous ARP to claim the IP.

This configuration expects a minimum of three control plane nodes for quorum.

## Migration Checklist (currently a work in progress)
Applications:
- [x] Minecraft Proxy + Limbo Server (mc.dsns.dev)
- [x] Web Proxy
  - [x] V2Ray VPN
  - [ ] Immich
  - [ ] T3 Code
- [ ] Wireguard VPN

## Deploy Talos Kubernetes Cluster + ArgoCD

1. Clone Homelab Repository
```bash
git clone https://github.com/dsnsgithub/homelab/
cd homelab
```
If you already have an existing Kubernetes cluster, skip steps 2 and 3.

2. Generate Config
```bash
talosctl gen config homelab https://10.3.3.8:6443 --config-patch @talos/controlplane-patch.yaml --output-dir _talos

# save secrets for later
talosctl gen secrets -o _talos/secrets.yaml --from-controlplane-config _talos/controlplane.yaml
```

3. Talos Configuration

Replace `<node-1>`, `<node-2>`, and `<node-3>` with the IPs of each node. Feel free to add more than three nodes just by appending more.

```bash
talosctl apply-config --insecure -n <node-1> --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-01.yaml
talosctl apply-config --insecure -n <node-2> --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-02.yaml
talosctl apply-config --insecure -n <node-3> --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-03.yaml

talosctl config merge _talos/talosconfig

talosctl config endpoint <node-1> <node-2> <node-3>
talosctl config node <node-1> <node-2> <node-3>

talosctl bootstrap -n <node-1>
talosctl kubeconfig -n 10.3.3.8

kubectl get nodes -A -o wide
```

4. Install ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
Be sure to disable any preinstalled load balancers and proxies such as ServiceLB and Traefik (if using k3s or similar) before deploying this repository.

5. Install Sealed Secrets controller + kubeseal
```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
```

Install the `kubeseal` CLI locally. Find files with `*.TEMPLATE.yaml` and generate the required secret.

6. Deploy Repository
```bash
kubectl apply -f argocd/root-app.yaml
```

Argo CD will watch files in `argocd/apps/`, any changes pushed to `main` will be synced/deployed within around 3 minutes.


## Additional Talos Information

To update Talos or add new nodes:
1. Update `controlplane-patch.yml` with new changes. If you want a custom name for your new node, add it in `talos/nodes/cp-xx.yaml`.

2. Generate new config
```bash
talosctl gen config homelab https://10.3.3.8:6443 \
  --with-secrets _talos/secrets.yaml \
  --config-patch-control-plane @talos/controlplane-patch.yaml \
  --output-dir _talos
```

3. Apply
```bash
talosctl apply-config --insecure -n <node-4> --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-04.yaml
talosctl config endpoint <node-4>
talosctl config node <node-4>
```
