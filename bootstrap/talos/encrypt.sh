#!/usr/bin/env bash
# Commits the current machine configs to git ENCRYPTED.
#
# Flow: patches (controlplane-patch.yaml + nodeN.yaml) are the human-editable
# intent; `gen-config.sh` renders them; this script bakes per-node plaintext
# and encrypts it into machines/*.sops.yaml — the committed, complete,
# declarative machine truth (secrets included, age-encrypted).
#
# Re-run after ANY patch/version change, then commit the result.
# Prereqs: talosctl (pinned, see gen-config.sh), sops, age key available
# (SOPS_AGE_KEY env var or ~/.config/sops/age/keys.txt).
set -euo pipefail
cd "$(dirname "$0")"
export TALOSCONFIG="$PWD/talosconfig"
# NOTE: sops resolves .sops.yaml from the CURRENT directory upward, so this
# cd above is load-bearing — run via ./encrypt.sh, not `bash path/encrypt.sh`
# from elsewhere (same holds for apply.sh/edit.sh).

command -v sops >/dev/null || { echo "error: sops not found (https://github.com/getsops/sops)"; exit 1; }
[ -f clusterconfig/controlplane.yaml ] || { echo "error: run ./gen-config.sh first"; exit 1; }

mkdir -p machines
for n in 1 2 3; do
  plain="machines/.plain-cp${n}.yaml"
  out="machines/cp${n}.sops.yaml"
  talosctl machineconfig patch clusterconfig/controlplane.yaml \
    --patch "@node${n}.yaml" --output "$plain"
  # .sops.yaml creation rules match the OUTPUT path (*.sops.yaml).
  sops --encrypt --in-place "$plain"
  mv "$plain" "$out"
  echo "encrypted: $out"
done
echo "commit the machines/*.sops.yaml files. Plaintext never leaves this machine (gitignored)."
