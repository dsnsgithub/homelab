#!/usr/bin/env bash
# Generates machine configs from the declarative patches in this directory.
#
# The patches + bootstrap/versions.env are the source of truth — NOT the
# output. Output contains secrets (certs/keys), so it is gitignored;
# regenerate any time with this script.
set -euo pipefail
cd "$(dirname "$0")"
source ../versions.env

command -v talosctl >/dev/null || {
  echo "error: talosctl not found. Install v${TALOS_VERSION}:"
  echo "  curl -sL https://github.com/siderolabs/talos/releases/download/v${TALOS_VERSION}/talosctl-linux-amd64 -o talosctl"
  exit 1
}
talosctl version --client 2>/dev/null | grep -q "${TALOS_VERSION}" || {
  echo "error: talosctl version skew. Install talosctl v${TALOS_VERSION} (matches bootstrap/versions.env)."
  talosctl version --client 2>/dev/null || true
  exit 1
}

rm -rf clusterconfig talosconfig
talosctl gen config "${CLUSTER_NAME}" "https://${CLUSTER_VIP}:6443" \
  --output-dir clusterconfig \
  --config-patch-control-plane @controlplane-patch.yaml
mv clusterconfig/talosconfig ./talosconfig

echo "generated:"
echo "  clusterconfig/controlplane.yaml  (shared base, contains secrets — gitignored)"
echo "  talosconfig                      (admin client config — gitignored, back it up)"
echo "next: boot each node into maintenance mode, then ./apply-node.sh nodeN.yaml <maintenance-ip>"
