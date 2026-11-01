# Bootstrap


## 0. Clone Repository and Install Dependencies

```bash
git clone https://github.com/dsnsgithub/homelab/
cd homelab
mise install
```

If you are rebuilding onto an existing healthy cluster, skip to [step 3](#3-install-argo-cd-and-sealed-secrets).


## 1. Download Talos ISOs and Boot VMs

Visit https://factory.talos.dev and download the ISOs for your platform, adding system extensions as needed.

Create the VMs by attaching the matching ISO. If you are using UTM, enable **Apple Virtualization** instead of QEMU to prevent etcd corruption on power loss and use **bridged** networking to give the VMs their own IP.

## 2. Generate Talos Config
On boot, each node enters maintenance mode, displaying a DHCP address. 

Edit `talos/topf.yaml` with the IPs of your nodes. Ensure each patch will work with your network configuration.

```bash
topf --topfconfig talos/topf.yaml apply --auto-bootstrap

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

## 3. Install Argo CD and Sealed Secrets

Restore the sealing keys first so existing `SealedSecret`s decrypt without re-sealing. After bootstrap, the `deploy` job applies this on every merge.

```bash
sops decrypt bootstrap/sealed-secrets/keys.yaml | kubectl apply --server-side -f -
kubectl apply --server-side --force-conflicts -k bootstrap
```

## 4. Deploy the Root App

This is the last manually executed command of the setup procedure. It points Argo CD at `argocd/apps` on `main`, and Argo CD installs the rest by itself within about 3 minutes.

```bash
kubectl apply -f argocd/root-app.yaml
```

Open the UI at `https://10.3.3.9` once `argocd-server-lb` receives its IP.
