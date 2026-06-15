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
  --clash-output PATH        Default: clash-meta.yaml beside --output
  --sing-box-output PATH     Default: sing-box-client.json beside --output
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
CLASH_OUTPUT=""
SING_BOX_OUTPUT=""

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
    --clash-output)
      CLASH_OUTPUT="${2:-}"
      shift 2
      ;;
    --sing-box-output)
      SING_BOX_OUTPUT="${2:-}"
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

VPN_DOMAIN="${VPN_DOMAIN:-${DOMAIN:-}}"
SUB_DOMAIN="${SUB_DOMAIN:-${VPN_DOMAIN}}"
NODE_NAME="${NODE_NAME:-${NAME:-VPN}}"

[[ -n "${VPN_DOMAIN:-}" ]] || die "VPN_DOMAIN missing in ${ENV_FILE}"
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
CLASH_OUTPUT="${CLASH_OUTPUT:-$(dirname "${OUTPUT}")/clash-meta.yaml}"
SING_BOX_OUTPUT="${SING_BOX_OUTPUT:-$(dirname "${OUTPUT}")/sing-box-client.json}"
install -d -m 0755 "$(dirname "${URI_OUTPUT}")"
install -d -m 0755 "$(dirname "${CLASH_OUTPUT}")"
install -d -m 0755 "$(dirname "${SING_BOX_OUTPUT}")"

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

cat >"${CLASH_OUTPUT}" <<EOF
mixed-port: 7890
allow-lan: false
mode: rule
log-level: warning
ipv6: false

proxies:
  - name: "${NODE_NAME}"
    type: trojan
    server: ${VPN_DOMAIN}
    port: 443
    password: "${TROJAN_PASSWORD}"
    sni: ${VPN_DOMAIN}
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: "${WS_PATH}"
      headers:
        Host: ${VPN_DOMAIN}

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - "${NODE_NAME}"
      - DIRECT

rules:
  - DOMAIN-SUFFIX,local,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT
  - IP-CIDR,172.16.0.0/12,DIRECT
  - IP-CIDR,192.168.0.0/16,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOF

python3 - "${VPN_DOMAIN}" "${NODE_NAME}" "${TROJAN_PASSWORD}" "${WS_PATH}" >"${SING_BOX_OUTPUT}" <<'PY'
import json
import sys

domain, node_name, password, ws_path = sys.argv[1:]
config = {
    "log": {"level": "warn", "timestamp": True},
    "dns": {
        "servers": [
            {"tag": "cf", "address": "1.1.1.1"},
            {"tag": "google", "address": "8.8.8.8"},
        ]
    },
    "inbounds": [
        {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 2080}
    ],
    "outbounds": [
        {
            "type": "trojan",
            "tag": node_name,
            "server": domain,
            "server_port": 443,
            "password": password,
            "tls": {"enabled": True, "server_name": domain},
            "transport": {"type": "ws", "path": ws_path, "headers": {"Host": domain}},
        },
        {"type": "direct", "tag": "direct"},
        {"type": "block", "tag": "block"},
    ],
    "route": {
        "rules": [
            {"ip_is_private": True, "outbound": "direct"},
            {"domain_suffix": ["local"], "outbound": "direct"},
            {"geoip": ["cn"], "outbound": "direct"},
        ],
        "final": node_name,
    },
}
print(json.dumps(config, ensure_ascii=False, indent=2))
PY

chmod 0644 "${OUTPUT}" "${URI_OUTPUT}" "${CLASH_OUTPUT}" "${SING_BOX_OUTPUT}"
echo "Regenerated ${OUTPUT}"
echo "Regenerated ${URI_OUTPUT}"
echo "Regenerated ${CLASH_OUTPUT}"
echo "Regenerated ${SING_BOX_OUTPUT}"
