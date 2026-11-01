#!/usr/bin/env bash
set -euo pipefail

lan_cidr=${LAN_CIDR:-10.3.3.0/24}
probe=${PROBE:-10.3.3.9:443}

sudo apt-get install -y -qq wireguard-tools >/dev/null

# wg-quick's DNS= needs resolvconf, which runners don't have.
printf '%s\n' "$WG_CONFIG" \
  | sed -E '/^\s*DNS\s*=/d; s|^\s*AllowedIPs\s*=.*|AllowedIPs = '"$lan_cidr"'|' \
  | sudo tee /etc/wireguard/wg0.conf >/dev/null
sudo chmod 600 /etc/wireguard/wg0.conf
sudo wg-quick up wg0

for _ in $(seq 1 15); do
  if timeout 3 bash -c "</dev/tcp/${probe%:*}/${probe#*:}" 2>/dev/null; then
    echo "Connected to $probe over WireGuard."
    exit 0
  fi
  sleep 2
done
echo "::error::WireGuard is up but $probe is unreachable."
sudo wg show
exit 1
