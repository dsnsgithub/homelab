# Talos GitOps

Commits to `main` that touch `talos/` automatically roll out to the nodes,
one node at a time with etcd health checks between each. Argo CD cannot do
this itself because Talos machine config lives outside Kubernetes (Talos API
on port 50000), so a LAN-reachable self-hosted GitHub Actions runner runs
`talosctl apply-config` on your behalf.

Flow: push/PR → `plan` job (GitHub-hosted, renders + validates configs) →
on merge to `main`, `apply` job (self-hosted, drains → applies → waits
`Ready` → checks etcd quorum → next node).

## Why raw talosctl, not talhelper (yet)

[talhelper](https://github.com/budimanjojo/talhelper) is the community
standard, and this was evaluated (Sep 2026, talhelper v3.1.17, Talos
v1.14.0). It cannot render this cluster today:

* Its patch decoder rejects the `KubeNodeConfig` and
  `UnattendedInstallConfig` documents (`not registered`), so the
  control-plane patch cannot be expressed.
* Its generated configs use the pre-1.14 schema: the
  `exclude-from-external-load-balancers` label (which production deletes
  for kube-vip) comes back, and the VIP-excluding `nodeIP.validSubnets`
  are lost. Applying that output would regress live behavior.

Talos 1.14 moved node taints/labels/IP into the new `KubeNodeConfig` kind
(and talhelper's maintainer notes multi-doc support is a known gap while
Talos keeps reshaping config documents). Re-evaluate talhelper once it
supports `KubeNodeConfig` patches — the workflow's plan/apply structure
stays the same, only the render step changes (`talhelper genconfig` +
SOPS-encrypted `talsecret.sops.yaml` instead of `talosctl gen config` +
GH-secret blobs).

## One-time setup

1. Give each node a stable address. Either set DHCP reservations on your
   router for the three nodes or switch them to static IPs, then put the
   real IPs in `talos/nodes.yaml` (it ships with `.21`/`.22`/`.23`
   placeholders). Keep `.8`/`.9`/`.10`/`.11` outside the DHCP pool as
   before. Hostnames in `nodes.yaml` must match `talos/nodes/cp-0N.yaml`.

2. Add a self-hosted runner on any always-on machine in `10.3.3.0/24`
   (Mac mini, Proxmox VM/LXC, NAS). It only needs outbound HTTPS plus TCP
   to the nodes on port 50000 and to the VIP on 6443:

   ```bash
   # On the runner machine (Linux/macOS, x64 or ARM):
   mkdir -p ~/actions-runner && cd ~/actions-runner
   # Get the token from GitHub: repo Settings > Actions > Runners > New self-hosted runner
   curl -o actions-runner.tar.gz -L <runner-tarball-url-from-github>
   tar xzf actions-runner.tar.gz
   ./config.sh --url https://github.com/dsnsgithub/homelab --token <token>
   sudo ./svc.sh install && sudo ./svc.sh start
   ```

   The workflow uses `runs-on: self-hosted`. If you run several runners,
   add a label (e.g. `./config.sh --labels talos`) and change both
   `runs-on` entries to `[self-hosted, talos]`.

3. Store the cluster credentials as Actions secrets
   (repo Settings > Secrets and variables > Actions).
   Generate each value with `base64 -w0 <file>` on macOS use `base64 -i <file>`:

   | Secret | Source |
   |--------|--------|
   | `TALOS_SECRETS_YAML_B64` | `_talos/secrets.yaml` (cluster PKI, irreplaceable) |
   | `TALOSCONFIG_B64` | `_talos/talosconfig` (admin access) |
   | `KUBECONFIG_B64` | `~/.kube/config` (optional; else fetched via `talosctl kubeconfig`) |

   ```bash
   gh secret set TALOS_SECRETS_YAML_B64 < <(base64 -w0 _talos/secrets.yaml)
   gh secret set TALOSCONFIG_B64 < <(base64 -w0 _talos/talosconfig)
   gh secret set KUBECONFIG_B64 < <(base64 -w0 ~/.kube/config)
   ```

## Day-to-day use

1. Edit `talos/controlplane-patch.yaml`, add/remove `talos/nodes/cp-0N.yaml`
   (and the matching `talos/nodes.yaml` entry), open a PR. The `plan` job
   validates the inventory and renders every node's full config.
2. Merge. The `apply` job drains, applies, waits `Ready`, and checks
   `talosctl etcd status` before moving to the next node. Watch it under
   Actions > talos-gitops.
3. If a node fails to come back, the job stops with that node cordoned
   (fail-closed so workloads stay off it). Fix forward or follow
   [Operations](operations.md) drain/repair steps, then `kubectl uncordon`.

Manual escape hatches (same commands the workflow runs):

```bash
talosctl gen config homelab https://10.3.3.8:6443 \
  --with-secrets _talos/secrets.yaml \
  --config-patch-control-plane @talos/controlplane-patch.yaml \
  --output-dir _talos --force
# Dry check one node without applying:
talosctl machineconfig patch _talos/controlplane.yaml \
  -p @talos/nodes/cp-01.yaml -o _talos/rendered-talos-m2.yaml
# Trigger apply without a push: Actions > talos-gitops > Run workflow (apply=true).
# Skip the runner for one commit: include [skip talos] in the message is NOT
# supported — instead push to a branch/PR without merging.
```

## Safety notes

* One node at a time, `concurrency.group: talos-gitops`, so overlapping
  pushes queue instead of racing etcd quorum.
* PRs from forks get inventory validation only (secrets are unavailable),
  so render output never leaks.
* `talosctl apply-config` reboots a node only when the change requires it;
  the workflow still drains first and waits for `Ready`, so no-change
  commits are cheap and disruptive ones are orderly.
* Rotating `_talos/secrets.yaml` or `talosconfig` means re-setting the
  matching Actions secret. `_talos/` stays gitignored and is never committed.
