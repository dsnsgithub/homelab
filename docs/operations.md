# Operations

## GitOps Workflow

Normal changes follow this loop, and no manual install commands are needed:

1. Edit manifests in `infra/` or `apps/`, or add `argocd/apps/<name>-app.yaml` for a new component.
2. Push to `main`.
3. Argo CD auto-syncs within about 3 minutes. Prune removes deleted objects, and selfHeal reverts manual `kubectl` edits.
4. Verify with `argocd app list` or in the UI at `https://10.3.3.9`.

`argocd/root-app.yaml` is the only object applied manually after bootstrap. Everything else is a child Application of the root.

## Regenerate Talos Config

After editing `talos/controlplane-patch.yaml`, re-render the configs from the saved master keys in `_talos/secrets.yaml`:

```bash
talosctl gen config homelab https://10.3.3.8:6443 \
  --with-secrets _talos/secrets.yaml \
  --config-patch-control-plane @talos/controlplane-patch.yaml \
  --output-dir _talos --force

talosctl apply-config -n <node-1> \
  --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-01.yaml
talosctl -n <node-1> reboot

talosctl apply-config -n <node-2> \
  --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-02.yaml
talosctl -n <node-2> reboot

talosctl apply-config -n <node-3> \
  --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-03.yaml
talosctl -n <node-3> reboot
```

## Add a Node

1. Add `talos/nodes/cp-04.yaml` with the new hostname, using the same `HostnameConfig` shape as the existing three files.
2. Regenerate the configs as shown above, then apply the new node config and register it:

```bash
talosctl apply-config --insecure -n <node-4> \
  --file _talos/controlplane.yaml --config-patch @talos/nodes/cp-04.yaml
talosctl config endpoint <node-1> <node-2> <node-3> <node-4>
talosctl config node <node-1> <node-2> <node-3> <node-4>
```

3. Verify membership and consensus with `talosctl etcd status` and `kubectl get nodes`.

## Upgrade Talos and Kubernetes

Upgrade one node at a time and wait for `Ready` between nodes. etcd needs 2 of 3 members online, so upgrading two nodes at once would stall writes:

```bash
talosctl upgrade -n <each-node> --image ghcr.io/siderolabs/installer:vX.Y.Z
```

## Repair a Crashlooping etcd Member

When `talosctl etcd status -n <node-1>,<node-2>,<node-3>`
returns only 2 of 3 rows, and `talosctl -n <failed-node> logs etcd` loops on
`service[etcd](Waiting): Error running Containerd(etcd)` with a raft panic:

```bash
talosctl etcd members -n <healthy-node>
talosctl etcd status -n <node-1>,<node-2>,<node-3>

talosctl -n <healthy-node> etcd remove-member <failed-member-id>
talosctl -n <failed-node> reset --graceful=false --reboot --system-labels-to-wipe=EPHEMERAL
```

Wait for the reboot, then verify it rejoins via the control-plane endpoint:

```bash
talosctl -n <node-1>,<node-2>,<node-3> etcd members
talosctl -n <node-1>,<node-2>,<node-3> etcd status
kubectl get nodes -o wide
```

Notes:

* If quorum is already lost, this procedure does not apply.
  Follow the full Sidero disaster recovery instead: snapshot via `talosctl cp`,
  wipe `EPHEMERAL` on the down nodes, and `talosctl bootstrap --recover-from`.

## Secrets

The two irreplaceable local artifacts are `_talos/secrets.yaml` (cluster PKI and credentials) and `talosconfig` (admin access), so keep copies offline. Everything else rebuilds from Git plus the sealed secrets.
