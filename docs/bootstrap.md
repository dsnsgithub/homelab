# Bootstrap

## Prerequisites

- `talosctl` (match Talos `v1.14.0`), `kubectl` (match K8s `v1.37.0`), `kubeseal`, `git`.
- 3 VMs (UTM × 2, Proxmox × 1) booted from Talos ISO, same L2 as `10.3.3.0/24`, bridged networking.
- LAN DHCP (or reservations) for `.189` / `.190` / `.192`; VIPs `.8`, `.9` (LB), `.10` free and outside the DHCP pool.
- Cloudflare API token (DNS-Edit) for cert-manager DNS-01.
- Domains delegated to Cloudflare: `dsns.dev`, `seung.dev`, `mseung.dev`.

## 1. Clone

```bash
git clone https://github.com/dsnsgithub/homelab/
cd homelab
```

If a working cluster exists, skip to [step 4](#4-install-argo-cd).

## 2. Generate Talos Config

```bash
talosctl gen config homelab https://10.3.3.8:6443 \
  --config-patch @talos/controlplane-patch.yaml \
  --output-dir _talos

# Persist for upgrades / new nodes — do not commit
talosctl gen secrets -o _talos/secrets.yaml \
  --from-controlplane-config _talos/controlplane.yaml
```

## 3. Apply Config & Bootstrap etcd

Replace `<node-1/2/3>` with `.189`, `.190`, `.192`. Add nodes by appending lines with a matching `talos/nodes/cp-0N.yaml` hostname patch.

```bash
talosctl apply-config --insecure -n <node-1> \
  --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-01.yaml
talosctl apply-config --insecure -n <node-2> \
  --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-02.yaml
talosctl apply-config --insecure -n <node-3> \
  --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-03.yaml

talosctl config merge _talos/talosconfig
talosctl config endpoint <node-1> <node-2> <node-3>
talosctl config node <node-1> <node-2> <node-3>

# Bootstrap etcd exactly once, on the first node
talosctl bootstrap -n <node-1>

# Kubeconfig via the HA VIP
talosctl kubeconfig -n 10.3.3.8
kubectl get nodes -A -o wide
```

Expect 3x `Ready` control-plane nodes. The API VIP `.8` can take ~30–60s.

## 4. Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

> On k3s or similar, disable bundled ServiceLB/Traefik first — kube-vip + this repo's Traefik own `.9`/`.10`.

## 5. Install Sealed Secrets

```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
```

For every `*.TEMPLATE.yaml`, create the plain Secret locally, seal against the cluster, commit only sealed output:

```bash
kubectl create secret generic velocity-config -n minecraft \
  --from-file=velocity.toml=./velocity.toml \
  --from-file=forwarding.secret=./forwarding.secret \
  --dry-run=client -o yaml | kubeseal -o yaml > apps/minecraft/velocity-secret.sealed.yaml
```

Current sealed inputs: `infra/cert-manager/cloudflare-secret`, `apps/minecraft/velocity-secret`, `apps/v2ray/v2ray-config`.

## 6. Deploy the Root App

```bash
kubectl apply -f argocd/root-app.yaml
```

Argo CD syncs everything under `argocd/apps` (prune + selfHeal, ~3 min poll). UI at `https://10.3.3.9`.
