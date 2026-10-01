# Bootstrap


## 0. Clone Repository and Install Dependencies

```bash
git clone https://github.com/dsnsgithub/homelab/
cd homelab
mise install
```

For an existing kube-vip/Flannel cluster, follow the [Cilium migration](cilium-migration.md) first. If the cluster already has healthy Cilium networking, skip to [step 4](#4-install-argo-cd).


## 1. Download Talos ISOs and Boot VMs

Visit https://factory.talos.dev and download the ISOs for your platform, adding system extensions as needed.

Create the VMs by attaching the matching ISO. If you are using UTM, enable **Apple Virtualization** instead of QEMU to prevent etcd corruption on power loss and use **bridged** networking to give the VMs their own IP.

## 2. Generate Talos Config
On boot, each node enters maintenance mode, displaying a DHCP address. 

Edit `talos/topf.yaml` with the IPs of your nodes. Ensure each patch will work with your network configuration.

```bash
topf --topfconfig talos/topf.yaml apply --auto-bootstrap --skip-post-apply-checks

age-keygen -o ~/.config/sops/age/keys.txt
# put public key in .sops.yaml
sops -e -i talos/secrets.yaml
```

If decrypting from current repo:
- Add your age public key to .sops.yaml, commit
- Encrypt the credentials with your public key on a computer with access: `sops updatekeys talos/secrets.yaml`

```bash
mkdir -p ~/.kube
topf --topfconfig talos/topf.yaml kubeconfig > ~/.kube/config

mkdir -p ~/.talos
topf --topfconfig talos/topf.yaml talosconfig > ~/.talos/config
```

## 3. Install Cilium

`talos/control-plane/03-cilium.yaml` disables Talos's Flannel and kube-proxy. These cluster-wide settings belong on control-plane nodes; Cilium agents run on all nodes. Nodes will remain NotReady until Cilium is installed. Install networking before Argo CD, because Argo CD itself needs working pod networking.

Cilium uses Talos's KubePrism endpoint at `localhost:7445`. Keep KubePrism enabled on every node. Reserve `10.3.3.9–11` outside the LAN's DHCP pool; `10.3.3.8` remains the Talos API VIP.

The pinned stable Cilium release is `1.20.2`. Its [tested Kubernetes matrix](https://docs.cilium.io/en/stable/network/kubernetes/requirements/) currently ends at `1.36`, whereas this repository targets `1.37`. Validate that combination on a test cluster before using it for the live cluster, or update the pin to a stable release that explicitly supports `1.37` when available.

```bash
helm template cilium cilium \
  --repo https://helm.cilium.io/ --version 1.20.2 \
  --namespace kube-system --values infra/cilium/values.yaml \
  | kubectl apply --server-side -f -

kubectl -n kube-system rollout status daemonset/cilium --timeout=5m
kubectl -n kube-system rollout status deployment/cilium-operator --timeout=5m
kubectl wait --for=condition=Ready nodes --all --timeout=5m
kubectl wait --for=condition=Established \
  crd/ciliumloadbalancerippools.cilium.io \
  crd/ciliuml2announcementpolicies.cilium.io --timeout=2m
kubectl apply --server-side -f infra/cilium/config/
```

This applies the same manifests that the `cilium` Argo CD application will manage, without creating a separate Helm release. After the root app syncs, Argo CD owns updates to Cilium and its load balancer configuration. Keep the bootstrap version above aligned with `argocd/apps/cilium-app.yaml`.

## 4. Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## 5. Install Sealed Secrets

The controller decrypts `SealedSecret` objects into regular Secrets at sync time. `kubeseal` runs locally against the cluster public certificate and performs the encryption. A fresh cluster generates a fresh controller certificate, so every secret must be re-sealed when rebuilding from scratch.

```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
```

For every sealed secret in the chart `values.yaml` files (under `sealedSecret:`), re-seal the plain input and paste the output into the chart's `encryptedData` before bootstrapping.

The currently sealed inputs are the Cloudflare token (`charts/cert-manager-config/values.yaml`), the Minecraft config (`charts/minecraft/values.yaml`), the V2Ray config (`charts/v2ray/values.yaml`), and the GitHub PR generator token (`charts/argocd-pr-generator/values.yaml`).

## 6. Deploy the Root App

This is the last manually executed command of the setup procedure. It points Argo CD at `argocd/apps` on `main`, and Argo CD installs the rest by itself within about 3 minutes.

```bash
kubectl apply -f argocd/root-app.yaml
```

Open the UI at `https://10.3.3.9` once `argocd-server-lb` receives its IP.
