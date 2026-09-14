#!/usr/bin/env bash
# Installs Talos on one node booted into maintenance mode, layering that
# node's identity patch (hostname, static IP, disk) onto the generated base.
#
# Usage: ./apply-node.sh node1.yaml <node's maintenance-mode IP>
# The maintenance IP is the DHCP address shown on the node's console after
# booting the Talos ISO. Repeat per node with its nodeN.yaml.
set -euo pipefail
cd "$(dirname "$0")"
export TALOSCONFIG="$PWD/talosconfig"

[ $# -eq 2 ] || { echo "usage: $0 <nodeN.yaml> <maintenance-ip>"; exit 1; }
[ -f clusterconfig/controlplane.yaml ] || { echo "error: run ./gen-config.sh first"; exit 1; }

talosctl apply --insecure -n "$2" \
  --file clusterconfig/controlplane.yaml \
  --config-patch "@$1"
echo "install triggered on $2 — the node wipes the disk, installs, and reboots onto its static IP."
