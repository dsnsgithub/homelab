# Talos GitOps

Commits to `main` that touch `talos/` automatically roll out to the nodes,
one node at a time with etcd health checks between each. Argo CD cannot do
this itself because Talos machine config lives outside Kubernetes (Talos API
on port 50000), so a LAN-reachable self-hosted GitHub Actions runner runs
[`topf`](https://github.com/postfinance/topf) (Talos orchestrator,
1.14-native) on your behalf.

Flow: push/PR → `plan` job (GitHub-hosted: `topf render` + `talosctl
validate`) → on merge to `main`, `apply` job (self-hosted: cluster
dry-run diff → per node: drain → `topf apply --nodes-filter` → wait
`Ready` → etcd quorum check → next node).

Layout: `talos/topf.yaml` (cluster identity + node list) composes small
patches in order `all/` → `control-plane/` → `node/<host>/`
(lexicographic within each dir). Secrets live in `talos/secrets.yaml`,
SOPS-encrypted with age, committed to git like everything else.

## Why TOPF, not talhelper

[talhelper](https://github.com/budimanjojo/talhelper) is the older
community standard and was evaluated first (Sep 2026, v3.1.17, Talos
v1.14.0). It cannot render this cluster: its patch decoder rejects the
`KubeNodeConfig` and `UnattendedInstallConfig` documents (`not
registered`), and its output uses the pre-1.14 schema (the
`exclude-from-external-load-balancers` label comes back, the
VIP-excluding `nodeIP.validSubnets` are lost). TOPF vendors Talos v1.14
machinery, supports multi-doc strategic-merge patches including
`$patch: delete` with no escaping hacks, and its render was verified
byte-for-byte behavior-preserving against the live config shape.

## One-time setup

1. Give each node a stable address. Either set DHCP reservations on your
   router for the three nodes or switch them to static IPs, then put the
   real IPs in `talos/topf.yaml` (it ships with `.21`/`.22`/`.23`
   placeholders). Keep `.8`/`.9`/`.10`/`.11` outside the DHCP pool as
   before.

2. Adopt the existing secrets bundle (one-time, on your workstation —
   this reuses the live cluster's PKI, no rebuild):

   ```bash
   # Install tools (macOS shown; see topf/sops/age releases for Linux):
   brew install postfinance/tap/topf sops age
   # Or with mise: mise use -g topf@0.6.0 sops@3.13.3 age@1.3.2

   # 1. Generate an age key and put the PUBLIC key in .sops.yaml
   age-keygen -o ~/.config/sops/age/keys.txt
   # 2. Copy the live secrets bundle into the repo (same format topf uses)
   cp _talos/secrets.yaml talos/secrets.yaml
   # 3. Encrypt in place (uses .sops.yaml creation rules) and commit
   sops -e -i talos/secrets.yaml
   git add talos/secrets.yaml && git commit -m "Add SOPS-encrypted Talos secrets bundle"
   ```

3. Add a self-hosted runner on any always-on machine in `10.3.3.0/24`
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
   add a label (e.g. `./config.sh --labels talos`) and change
   `runs-on` to `[self-hosted, talos]`. The workflow installs
   topf/sops/talosctl/kubectl itself, so the runner needs no tooling.

4. Store secrets (repo Settings > Secrets and variables > Actions):

   | Secret | Source |
   |--------|--------|
   | `SOPS_AGE_KEY` | The age **private** key (`AGE-SECRET-KEY-...` line from step 2 — the only secret CI needs) |
   | `KUBECONFIG_B64` | `~/.kube/config`, base64 (optional; else minted via `topf kubeconfig`, 12h validity) |

   ```bash
   grep '^AGE-SECRET-KEY' ~/.config/sops/age/keys.txt | gh secret set SOPS_AGE_KEY --body-file -
   gh secret set KUBECONFIG_B64 < <(base64 -w0 ~/.kube/config) # macOS: base64 -i ~/.kube/config
   ```

   Keep an offline copy of the age key and `_talos/` — losing both means
   re-sealing secrets and re-issuing access, same as before.

## Day-to-day use

1. Edit a patch (`talos/all/`, `talos/control-plane/`, `talos/node/<host>/`),
   bump versions in `talos/topf.yaml`, or add a node entry. Preview locally:

   ```bash
   export SOPS_AGE_KEY=$(grep '^AGE-SECRET-KEY' ~/.config/sops/age/keys.txt)
   topf --topfconfig talos/topf.yaml render -o /tmp/rendered
   topf --topfconfig talos/topf.yaml apply --dry-run # diff vs live nodes, exit 2 = changes
   ```

   Open a PR. The `plan` job renders and validates every node's config.
2. Merge. The `apply` job shows the cluster diff, then drains, applies
   (TOPF pre-flights health and stabilizes each node itself), waits
   `Ready`, and checks `talosctl etcd status` before moving to the next
   node. Watch it under Actions > talos-gitops.
3. If a node fails to come back, the job stops with that node cordoned
   (fail-closed so workloads stay off it). Fix forward or follow
   [Operations](operations.md) drain/repair steps, then `kubectl uncordon`.

Manual escape hatches:

```bash
# Render offline / diff against live nodes without applying:
topf --topfconfig talos/topf.yaml render -o /tmp/rendered
topf --topfconfig talos/topf.yaml apply --dry-run
# Single node, e.g. after adding talos-m2:
topf --topfconfig talos/topf.yaml apply --nodes-filter "^talos-m2$" --confirm=false
# Talos version upgrades (applies installer image bumps node by node):
topf --topfconfig talos/topf.yaml upgrade --confirm=false
# Trigger apply without a push: Actions > talos-gitops > Run workflow (apply=true).
```

## Safety notes

* One node at a time (`--nodes-filter` loop in inventory order) plus
  `concurrency.group: talos-gitops`, so overlapping pushes queue instead
  of racing etcd quorum. TOPF aborts on unhealthy nodes unless told
  otherwise — the workflow does not pass `--skip-problematic-nodes`.
* PRs from forks get no plan output (age key unavailable), so rendered
  configs and secrets never leak. TOPF redacts secrets from diffs by
  default (`--redact=true`).
* `apply` reboots a node only when the change requires it (`--mode auto`);
  the workflow still drains first and waits for `Ready`, so no-change
  commits are cheap and disruptive ones are orderly.
* Rotating the age key: generate a new one, `sops updatekeys
  talos/secrets.yaml`, update `SOPS_AGE_KEY`.
