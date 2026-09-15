#!/usr/bin/env bash
#
# Generate a stateless WireGuard server config and seal it for GitOps.
#
# The server key and every peer key are generated OFFLINE by this script.
# The cluster itself holds no persistent state: at Pod start the
# initContainer renders /config/wg_confs/wg0.conf from the SealedSecret into
# an in-memory emptyDir, so a rescheduled Pod comes back with byte-identical
# config. Losing apps/wireguard/.peers/ means re-issuing peer configs, so
# back that directory up offline (it is gitignored and must never be
# committed - peer .conf files contain private keys).
#
# Usage:
#   apps/wireguard/gen-wireguard-secret.sh --peers laptop,phone [--seal]
#
# Full options:
#   --peers NAME,...      comma-separated peer names, [A-Za-z0-9_-] only (required)
#   --endpoint HOST:PORT  server endpoint baked into client configs
#                         (default: 10.3.3.11:51820; use your DDNS name + a
#                         UDP 51820 port-forward for WAN access)
#   --subnet-base A.B.C   /24 for the VPN, server takes .1 (default: 10.13.13)
#   --dns IP,...          client DNS (default: 10.96.0.10,1.1.1.1;
#                         10.96.0.10 is the Talos cluster CoreDNS)
#   --seal                also run kubeseal into wireguard-secret.sealed.yaml
#                         (needs cluster access; otherwise the exact command
#                         is printed for you to run later)
#   --rotate-server       generate a FRESH server key (invalidates ALL
#                         existing peers). Default reuses .peers/server-private.key
#                         when present so adding a peer never breaks the rest.
#
# Requirements: wg (wireguard-tools). kubeseal + kubectl only for --seal.
# Override the wireguard binary for testing with WG_BIN=/path/to/wg.
#
set -euo pipefail
umask 077

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PEERS_DIR="$APP_DIR/.peers"
PLAIN_OUT="$APP_DIR/wireguard-secret.plain.yaml"
SEALED_OUT="$APP_DIR/wireguard-secret.sealed.yaml"

PEERS=""
ENDPOINT="10.3.3.11:51820"
SUBNET_BASE="10.13.13"
DNS="10.96.0.10,1.1.1.1"
SEAL=0
ROTATE_SERVER=0
WG_BIN="${WG_BIN:-wg}"

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --peers) PEERS="${2:?}"; shift 2 ;;
    --endpoint) ENDPOINT="${2:?}"; shift 2 ;;
    --subnet-base) SUBNET_BASE="${2:?}"; shift 2 ;;
    --dns) DNS="${2:?}"; shift 2 ;;
    --seal) SEAL=1; shift ;;
    --rotate-server) ROTATE_SERVER=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown flag $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -n "$PEERS" ]] || { echo "error: --peers is required (e.g. --peers laptop,phone)" >&2; exit 1; }
command -v "$WG_BIN" >/dev/null || { echo "error: '$WG_BIN' not found (apt install wireguard-tools)" >&2; exit 1; }

IFS=',' read -ra PEER_NAMES <<< "$PEERS"
((${#PEER_NAMES[@]} >= 1 && ${#PEER_NAMES[@]} <= 253)) || { echo "error: peer count must be 1-253" >&2; exit 1; }
for p in "${PEER_NAMES[@]}"; do
  [[ "$p" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "error: bad peer name '$p' (use [A-Za-z0-9_-])" >&2; exit 1; }
done
# Reject duplicates: adding the same name twice would assign one IP to two keys.
# (tr -d ' ' because BSD/macOS wc -l pads its output with spaces.)
if [[ "$(printf '%s\n' "${PEER_NAMES[@]}" | sort -u | wc -l | tr -d ' ')" != "${#PEER_NAMES[@]}" ]]; then
  echo "error: duplicate peer names" >&2; exit 1
fi
[[ "$ENDPOINT" == *:* ]] || { echo "error: --endpoint must be HOST:PORT" >&2; exit 1; }
[[ "$SUBNET_BASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: --subnet-base must look like 10.13.13" >&2; exit 1; }

mkdir -p "$PEERS_DIR"

# --- server keypair (stable across runs unless rotated) ---
if [[ "$ROTATE_SERVER" -eq 0 && -f "$PEERS_DIR/server-private.key" ]]; then
  SERVER_PRIV="$(cat "$PEERS_DIR/server-private.key")"
  echo "reusing existing server key ($PEERS_DIR/server-private.key)"
else
  SERVER_PRIV="$("$WG_BIN" genkey)"
  printf '%s' "$SERVER_PRIV" > "$PEERS_DIR/server-private.key"
  [[ "$ROTATE_SERVER" -eq 1 ]] && echo "rotated: fresh server key generated (all old peers invalid)"
fi
SERVER_PUB="$(printf '%s' "$SERVER_PRIV" | "$WG_BIN" pubkey)"
printf '%s' "$SERVER_PUB" > "$PEERS_DIR/server-public.key"

# --- server wg0.conf ---
WG_CONF="$(mktemp)"
{
  echo "[Interface]"
  echo "Address = ${SUBNET_BASE}.1/24"
  echo "ListenPort = 51820"
  echo "PrivateKey = ${SERVER_PRIV}"
  echo "MTU = 1420"
  echo "PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
  echo "PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE"
} > "$WG_CONF"

# Split-tunnel routes pushed to clients: VPN subnet itself plus the homelab
# LAN, pod and service CIDRs. Replace with "0.0.0.0/0, ::/0" for full tunnel.
CLIENT_ALLOWED="10.3.3.0/24, 10.244.0.0/16, 10.96.0.0/12, ${SUBNET_BASE}.0/24"

i=2
for p in "${PEER_NAMES[@]}"; do
  PEER_PRIV="$("$WG_BIN" genkey)"
  PEER_PUB="$(printf '%s' "$PEER_PRIV" | "$WG_BIN" pubkey)"
  PEER_PSK="$("$WG_BIN" genpsk)"
  PEER_IP="${SUBNET_BASE}.${i}"
  {
    echo ""
    echo "[Peer]"
    echo "# ${p} - ${PEER_IP}/32"
    echo "PublicKey = ${PEER_PUB}"
    echo "PresharedKey = ${PEER_PSK}"
    echo "AllowedIPs = ${PEER_IP}/32"
    echo "PersistentKeepalive = 25"
  } >> "$WG_CONF"
  {
    echo "[Interface]"
    echo "PrivateKey = ${PEER_PRIV}"
    echo "Address = ${PEER_IP}/24"
    echo "DNS = ${DNS}"
    echo ""
    echo "[Peer]"
    echo "PublicKey = ${SERVER_PUB}"
    echo "PresharedKey = ${PEER_PSK}"
    echo "Endpoint = ${ENDPOINT}"
    echo "AllowedIPs = ${CLIENT_ALLOWED}"
    echo "PersistentKeepalive = 25"
  } > "$PEERS_DIR/${p}.conf"
  echo "wrote $PEERS_DIR/${p}.conf (${PEER_IP})"
  i=$((i + 1))
done

# --- plain Secret (gitignored via *.plain.yaml), then seal ---
{
  echo "apiVersion: v1"
  echo "kind: Secret"
  echo "metadata:"
  echo "  name: wireguard-config"
  echo "  namespace: wireguard-vpn"
  echo "type: Opaque"
  echo "stringData:"
  echo "  wg0.conf: |"
  sed 's/^/    /' "$WG_CONF"
} > "$PLAIN_OUT"
rm -f "$WG_CONF"
echo "wrote $PLAIN_OUT"

SEAL_CMD="kubeseal --format yaml --controller-name sealed-secrets-controller --controller-namespace kube-system < \"$PLAIN_OUT\" > \"$SEALED_OUT\""
if [[ "$SEAL" -eq 1 ]]; then
  # shellcheck disable=SC2094
  eval "$SEAL_CMD"
  echo "sealed -> $SEALED_OUT"
else
  echo "next: seal and commit ONLY the sealed output (never the plain file or .peers/):"
  echo "  $SEAL_CMD"
fi
echo "server public key: $SERVER_PUB"
echo "mobile import hint: qrencode -t ansiutf8 < \"$PEERS_DIR/<peer>.conf\" (if qrencode is installed)"
