#!/usr/bin/env bash
# Applies a COMMITTED ENCRYPTED machine config to a node — no plaintext ever
# written to disk (sops decrypts to a temp file it cleans up itself).
#
# Install:  ./apply.sh machines/cp1.sops.yaml <maintenance-ip> --insecure
# Reconfig: ./apply.sh machines/cp1.sops.yaml <node-static-ip>
# (extra talosctl flags like --insecure pass straight through)
set -euo pipefail
cd "$(dirname "$0")"
export TALOSCONFIG="$PWD/talosconfig"

command -v sops >/dev/null || { echo "error: sops not found (https://github.com/getsops/sops)"; exit 1; }
[ $# -ge 2 ] || { echo "usage: $0 <machines/cpN.sops.yaml> <node-ip> [talosctl flags...]"; exit 1; }
FILE="$1"; ADDR="$2"; shift 2

sops exec-file "$FILE" "talosctl apply --file {} -n '$ADDR' $*"
echo "applied $FILE to $ADDR"
