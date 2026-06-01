#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Regenerate the Shadowrocket subscription file from existing deployment secrets.

Usage:
  sudo bash refresh-subscription.sh [options]

Options:
  --env-file PATH            Default: /root/vpn-deploy.env
  --rules-file PATH          Default: ./shadowrocket-rules.conf, then /root/shadowrocket-rules.conf
  --output PATH              Default: /opt/shadowrocket-sub/shadowrocket.conf
  --uri-output PATH          Default: trojan-uri.txt beside --output
  -h, --help                 Show this help.
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

urlencode() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=""))
PY
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="/root/vpn-deploy.env"
RULES_FILE=""
OUTPUT="/opt/shadowrocket-sub/shadowrocket.conf"
URI_OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --rules-file)
      RULES_FILE="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT="${2:-}"
      shift 2
      ;;
    --uri-output)
      URI_OUTPUT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -f "${ENV_FILE}" ]] || die "Env file not found: ${ENV_FILE}"
# shellcheck disable=SC1090
. "${ENV_FILE}"

[[ -n "${VPN_DOMAIN:-}" ]] || die "VPN_DOMAIN missing in ${ENV_FILE}"
[[ -n "${NODE_NAME:-}" ]] || die "NODE_NAME missing in ${ENV_FILE}"
[[ -n "${TROJAN_PASSWORD:-}" ]] || die "TROJAN_PASSWORD missing in ${ENV_FILE}"
[[ -n "${WS_PATH:-}" ]] || die "WS_PATH missing in ${ENV_FILE}"

if [[ -z "${RULES_FILE}" ]]; then
  if [[ -f "${SCRIPT_DIR}/shadowrocket-rules.conf" ]]; then
    RULES_FILE="${SCRIPT_DIR}/shadowrocket-rules.conf"
  elif [[ -f /root/shadowrocket-rules.conf ]]; then
    RULES_FILE="/root/shadowrocket-rules.conf"
  else
    die "No rules file found. Pass --rules-file PATH."
  fi
fi
[[ -f "${RULES_FILE}" ]] || die "Rules file not found: ${RULES_FILE}"

install -d -m 0755 "$(dirname "${OUTPUT}")"
URI_OUTPUT="${URI_OUTPUT:-$(dirname "${OUTPUT}")/trojan-uri.txt}"
install -d -m 0755 "$(dirname "${URI_OUTPUT}")"

encoded_password="$(urlencode "${TROJAN_PASSWORD}")"
encoded_path="$(urlencode "${WS_PATH}")"
encoded_name="$(urlencode "${NODE_NAME}")"
trojan_uri="trojan://${encoded_password}@${VPN_DOMAIN}:443?security=tls&sni=${VPN_DOMAIN}&type=ws&host=${VPN_DOMAIN}&path=${encoded_path}#${encoded_name}"

cat >"${OUTPUT}" <<EOF
[General]
bypass-system = true
skip-proxy = 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, localhost, *.local, captive.apple.com
tun-excluded-routes = 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24, 192.88.99.0/24, 192.168.0.0/16, 198.51.100.0/24, 203.0.113.0/24, 224.0.0.0/4, 255.255.255.255/32, 239.255.255.250/32
dns-server = system
fallback-dns-server = system
ipv6 = true
prefer-ipv6 = false
dns-direct-system = false
icmp-auto-reply = true
always-reject-url-rewrite = false
private-ip-answer = true
dns-direct-fallback-proxy = false
udp-policy-not-supported-behaviour = REJECT
use-local-host-item-for-proxy = false

[Proxy]
${NODE_NAME} = trojan, ${VPN_DOMAIN}, 443, password=${TROJAN_PASSWORD}, over-tls=true, tls-verification=true, udp-relay=true, tfo=true, obfs=websocket, obfs-host=${VPN_DOMAIN}, obfs-uri=${WS_PATH}

[Proxy Group]
PROXY = select, ${NODE_NAME}, DIRECT

[Rule]
EOF

cat "${RULES_FILE}" >>"${OUTPUT}"

cat >>"${OUTPUT}" <<'EOF'

[Host]
localhost = 127.0.0.1
EOF

cat >"${URI_OUTPUT}" <<EOF
${trojan_uri}
EOF

chmod 0644 "${OUTPUT}" "${URI_OUTPUT}"
echo "Regenerated ${OUTPUT}"
