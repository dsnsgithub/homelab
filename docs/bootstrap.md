# Bootstrap


## 0. Clone Repository and Install Dependencies

```bash
git clone https://github.com/dsnsgithub/homelab/
cd homelab
mise install
```

If you are rebuilding onto an existing healthy cluster, skip to [step 4](#4-install-argo-cd).


## 1. Download Talos ISOs and Boot VMs

Visit https://factory.talos.dev and download the ISOs for your platform, adding system extensions as needed.

Create the VMs by attaching the matching ISO. If you are using UTM, enable **Apple Virtualization** instead of QEMU to prevent etcd corruption on power loss and use **bridged** networking to give the VMs their own IP.

## 2. Generate Talos Config
On boot, each node enters maintenance mode, displaying a DHCP address. 

Edit `talos/topf.yaml` with the IPs of your nodes. Ensure each patch will work with your network configuration.

```bash
topf apply --auto-bootstrap
topf kubeconfig
topf talosconfig
```

## 3. Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## 4. Install Sealed Secrets

The controller decrypts `SealedSecret` objects into regular Secrets at sync time. `kubeseal` runs locally against the cluster public certificate and performs the encryption. A fresh cluster generates a fresh controller certificate, so every secret must be re-sealed when rebuilding from scratch.

```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
```

For every `*.TEMPLATE.yaml` file, build the plain Secret locally, seal it, and commit only the sealed output. The following example seals the Minecraft config:

```bash
kubectl create secret generic velocity-config -n minecraft \
  --from-file=velocity.toml=./velocity.toml \
  --from-file=forwarding.secret=./forwarding.secret \
  --dry-run=client -o yaml | kubeseal -o yaml > apps/minecraft/velocity-secret.sealed.yaml
```

The currently sealed inputs are the Cloudflare token (`infra/cert-manager/cloudflare-secret.sealed.yaml`), the Minecraft config (`apps/minecraft/velocity-secret.sealed.yaml`), and the V2Ray config (`apps/v2ray/v2ray-secret.sealed.yaml`).

## 5. Deploy the Root App

This is the last manually executed command of the setup procedure. It points Argo CD at `argocd/apps` on `main`, and Argo CD installs the rest by itself within about 3 minutes.

```bash
kubectl apply -f argocd/root-app.yaml
```

Open the UI at `https://10.3.3.9` once `argocd-server-lb` receives its IP.