#!/usr/bin/env bash
# Edits a committed encrypted machine config in place ($EDITOR on decrypted
# content, re-encrypted on save). For version bumps and small tweaks; for
# structural changes prefer editing the patches + gen-config.sh + encrypt.sh.
# Usage: ./edit.sh machines/cp1.sops.yaml
set -euo pipefail
cd "$(dirname "$0")"
[ $# -eq 1 ] || { echo "usage: $0 <machines/cpN.sops.yaml>"; exit 1; }
sops "$1"
