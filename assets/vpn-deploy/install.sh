#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Nginx/VPS self-hosted access service installer.

Usage:
  sudo bash install.sh --vpn-domain vpn.example.com --sub-domain vpn.example.com [options]

Required:
  --vpn-domain DOMAIN        Domain used by Shadowrocket node traffic.
  --sub-domain DOMAIN        Domain used by the private subscription URL. Can equal --vpn-domain.

Options:
  --email EMAIL              ACME email for Caddy/Let's Encrypt.
  --node-name NAME           Shadowrocket node name. Default: Nginx/VPSVPN.
  --rules-file PATH          Shadowrocket rules file. Default: ./shadowrocket-rules.conf if present.
  --web-server MODE          caddy, nginx, or none. Default: caddy.
  --sub-auth-user USER       Basic Auth user for subscription URLs. Default: generated.
  --sub-auth-password PASS   Basic Auth password for subscription URLs. Default: generated.
  --trojan-password VALUE    Existing Trojan password. Default: generated.
  --ws-path PATH             WebSocket path. Default: generated.
  --sub-path PATH            Subscription path. Default: generated.
  --ssh-port PORT            SSH port to keep open in UFW. Default: 22.
  --skip-ufw                 Do not configure or enable UFW.
  -h, --help                 Show this help.

Notes:
  - Point both subdomains to this server before running the installer.
  - The public firewall exposure is SSH, HTTP/80, and HTTPS/443.
  - This script does not configure traffic evasion, residential IP spoofing,
    or platform risk bypassing.
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Run as root: sudo bash install.sh ..."
  fi
}

random_token() {
  local len="${1:-32}"
  openssl rand -hex "$(((len + 1) / 2))" | cut -c "1-${len}"
}

clean_path() {
  local raw="$1"
  raw="${raw%%[[:space:]]*}"
  [[ "${raw}" == /* ]] || raw="/${raw}"
  echo "${raw}"
}

urlencode() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=""))
PY
}

write_env_line() {
  printf '%s=%q\n' "$1" "$2" >>/root/vpn-deploy.env
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VPN_DOMAIN=""
SUB_DOMAIN=""
EMAIL=""
NODE_NAME="Nginx/VPSVPN"
RULES_FILE=""
TROJAN_PASSWORD=""
WS_PATH=""
SUB_PATH=""
SUB_AUTH_USER=""
SUB_AUTH_PASSWORD=""
SSH_PORT="22"
SKIP_UFW="0"
WEB_SERVER="caddy"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vpn-domain)
      VPN_DOMAIN="${2:-}"
      shift 2
      ;;
    --sub-domain)
      SUB_DOMAIN="${2:-}"
      shift 2
      ;;
    --email)
      EMAIL="${2:-}"
      shift 2
      ;;
    --node-name)
      NODE_NAME="${2:-}"
      shift 2
      ;;
    --rules-file)
      RULES_FILE="${2:-}"
      shift 2
      ;;
    --web-server)
      WEB_SERVER="${2:-caddy}"
      shift 2
      ;;
    --sub-auth-user)
      SUB_AUTH_USER="${2:-}"
      shift 2
      ;;
    --sub-auth-password)
      SUB_AUTH_PASSWORD="${2:-}"
      shift 2
      ;;
    --trojan-password)
      TROJAN_PASSWORD="${2:-}"
      shift 2
      ;;
    --ws-path)
      WS_PATH="$(clean_path "${2:-}")"
      shift 2
      ;;
    --sub-path)
      SUB_PATH="$(clean_path "${2:-}")"
      shift 2
      ;;
    --ssh-port)
      SSH_PORT="${2:-22}"
      shift 2
      ;;
    --skip-ufw)
      SKIP_UFW="1"
      shift
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

need_root
[[ -n "${VPN_DOMAIN}" ]] || die "--vpn-domain is required"
[[ -n "${SUB_DOMAIN}" ]] || die "--sub-domain is required"
[[ "${SSH_PORT}" =~ ^[0-9]+$ ]] || die "--ssh-port must be numeric"
case "${WEB_SERVER}" in
  caddy|nginx|none) ;;
  *) die "--web-server must be caddy, nginx, or none" ;;
esac

if [[ ! -f /etc/os-release ]]; then
  die "This installer expects Ubuntu/Debian with /etc/os-release"
fi

# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *) die "Unsupported OS '${ID:-unknown}'. Use Ubuntu 22.04/24.04 or Debian 12." ;;
esac

TROJAN_PASSWORD="${TROJAN_PASSWORD:-$(random_token 40)}"
WS_PATH="${WS_PATH:-/$(random_token 18)}"
SUB_PATH="${SUB_PATH:-/sub/$(random_token 24)}"
SUB_AUTH_USER="${SUB_AUTH_USER:-sr_$(random_token 8)}"
SUB_AUTH_PASSWORD="${SUB_AUTH_PASSWORD:-$(random_token 36)}"

install_base_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    debian-archive-keyring \
    debian-keyring \
    gpg \
    gzip \
    lsb-release \
    openssl \
    python3 \
    tar \
    ufw
}

install_sing_box() {
  local arch version url tmp_dir binary
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "Unsupported CPU architecture: $(uname -m)" ;;
  esac

  version="${SING_BOX_VERSION:-}"
  if [[ -z "${version}" ]]; then
    version="$(
      curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest \
        | sed -n 's/.*"tag_name": "v\([^"]*\)".*/\1/p' \
        | head -n 1
    )"
  fi
  [[ -n "${version}" ]] || die "Could not determine latest sing-box version"

  url="https://github.com/SagerNet/sing-box/releases/download/v${version}/sing-box-${version}-linux-${arch}.tar.gz"
  tmp_dir="$(mktemp -d)"
  curl -fL "${url}" -o "${tmp_dir}/sing-box.tar.gz"
  tar -xzf "${tmp_dir}/sing-box.tar.gz" -C "${tmp_dir}"
  binary="$(find "${tmp_dir}" -type f -name sing-box -perm -111 | head -n 1)"
  [[ -n "${binary}" ]] || die "sing-box binary not found in release archive"
  install -m 0755 "${binary}" /usr/local/bin/sing-box
  rm -rf "${tmp_dir}"
}

install_caddy() {
  rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  chmod o+r /etc/apt/sources.list.d/caddy-stable.list

  apt-get update
  apt-get install -y caddy
}

write_nginx_config_draft() {
  local htpasswd_line
  htpasswd_line="${SUB_AUTH_USER}:$(openssl passwd -apr1 "${SUB_AUTH_PASSWORD}")"
  if [[ "${VPN_DOMAIN}" == "${SUB_DOMAIN}" ]]; then
    cat >/root/vpn-deploy-nginx.conf <<EOF
# Draft Nginx config for Self-hosted VPN single-domain deployment.
# Review paths and install certificates before enabling.
#
# Expected certificate:
#   /etc/letsencrypt/live/${VPN_DOMAIN}/fullchain.pem
#   /etc/letsencrypt/live/${VPN_DOMAIN}/privkey.pem
#
# Before enabling, create the subscription password file:
#   printf '%s\n' '${htpasswd_line}' > /etc/nginx/.htpasswd-vpn-sub
#   chown root:www-data /etc/nginx/.htpasswd-vpn-sub
#   chmod 640 /etc/nginx/.htpasswd-vpn-sub

server {
  listen 80;
  listen [::]:80;
  server_name ${VPN_DOMAIN};

  location /.well-known/acme-challenge/ {
    root /var/www/html;
  }

  location / {
    return 301 https://\$host\$request_uri;
  }
}

server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name ${VPN_DOMAIN};

  ssl_certificate /etc/letsencrypt/live/${VPN_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${VPN_DOMAIN}/privkey.pem;

  root /opt/shadowrocket-sub;

  location = ${WS_PATH} {
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 86400;
    proxy_pass http://127.0.0.1:10000;
  }

  location = ${SUB_PATH} {
    auth_basic "Shadowrocket subscription";
    auth_basic_user_file /etc/nginx/.htpasswd-vpn-sub;
    try_files /shadowrocket.conf =404;
    default_type text/plain;
  }

  location = ${SUB_PATH}/server {
    auth_basic "Shadowrocket subscription";
    auth_basic_user_file /etc/nginx/.htpasswd-vpn-sub;
    try_files /trojan-uri.txt =404;
    default_type text/plain;
  }

  location = ${SUB_PATH}/clash {
    auth_basic "VPN subscription";
    auth_basic_user_file /etc/nginx/.htpasswd-vpn-sub;
    try_files /clash-meta.yaml =404;
    default_type text/yaml;
  }

  location = ${SUB_PATH}/sing-box {
    auth_basic "VPN subscription";
    auth_basic_user_file /etc/nginx/.htpasswd-vpn-sub;
    try_files /sing-box-client.json =404;
    default_type application/json;
  }

  location / {
    return 404;
  }
}
EOF
  else
    cat >/root/vpn-deploy-nginx.conf <<EOF
# Draft Nginx config for Self-hosted VPN subdomains.
# Review paths and install certificates before enabling.
#
# Expected certificates:
#   /etc/letsencrypt/live/${VPN_DOMAIN}/fullchain.pem
#   /etc/letsencrypt/live/${VPN_DOMAIN}/privkey.pem
#   /etc/letsencrypt/live/${SUB_DOMAIN}/fullchain.pem
#   /etc/letsencrypt/live/${SUB_DOMAIN}/privkey.pem
#
# Typical enable flow:
#   printf '%s\n' '${htpasswd_line}' > /etc/nginx/.htpasswd-vpn-sub
#   chown root:www-data /etc/nginx/.htpasswd-vpn-sub
#   chmod 640 /etc/nginx/.htpasswd-vpn-sub
#   cp /root/vpn-deploy-nginx.conf /etc/nginx/sites-available/vpn-deploy
#   ln -s /etc/nginx/sites-available/vpn-deploy /etc/nginx/sites-enabled/vpn-deploy
#   nginx -t && systemctl reload nginx

server {
  listen 80;
  listen [::]:80;
  server_name ${VPN_DOMAIN} ${SUB_DOMAIN};

  location /.well-known/acme-challenge/ {
    root /var/www/html;
  }

  location / {
    return 301 https://\$host\$request_uri;
  }
}

server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name ${VPN_DOMAIN};

  ssl_certificate /etc/letsencrypt/live/${VPN_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${VPN_DOMAIN}/privkey.pem;

  location = ${WS_PATH} {
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 86400;
    proxy_pass http://127.0.0.1:10000;
  }

  location / {
    return 404;
  }
}

server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name ${SUB_DOMAIN};

  ssl_certificate /etc/letsencrypt/live/${SUB_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${SUB_DOMAIN}/privkey.pem;

  root /opt/shadowrocket-sub;

  location = ${SUB_PATH} {
    auth_basic "Shadowrocket subscription";
    auth_basic_user_file /etc/nginx/.htpasswd-vpn-sub;
    try_files /shadowrocket.conf =404;
    default_type text/plain;
  }

  location = ${SUB_PATH}/server {
    auth_basic "Shadowrocket subscription";
    auth_basic_user_file /etc/nginx/.htpasswd-vpn-sub;
    try_files /trojan-uri.txt =404;
    default_type text/plain;
  }

  location = ${SUB_PATH}/clash {
    auth_basic "VPN subscription";
    auth_basic_user_file /etc/nginx/.htpasswd-vpn-sub;
    try_files /clash-meta.yaml =404;
    default_type text/yaml;
  }

  location = ${SUB_PATH}/sing-box {
    auth_basic "VPN subscription";
    auth_basic_user_file /etc/nginx/.htpasswd-vpn-sub;
    try_files /sing-box-client.json =404;
    default_type application/json;
  }

  location / {
    return 404;
  }
}
EOF
  fi
  chmod 0600 /root/vpn-deploy-nginx.conf
}

write_sing_box_config() {
  install -d -m 0755 /etc/sing-box
  if [[ -f /etc/sing-box/config.json ]]; then
    cp /etc/sing-box/config.json "/etc/sing-box/config.json.bak.$(date +%Y%m%d%H%M%S)"
  fi

  cat >/etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-ws-in",
      "listen": "127.0.0.1",
      "listen_port": 10000,
      "users": [
        {
          "name": "${NODE_NAME}",
          "password": "${TROJAN_PASSWORD}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${WS_PATH}"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "final": "direct"
  }
}
EOF
}

write_systemd_unit() {
  cat >/etc/systemd/system/sing-box.service <<'EOF'
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
User=root
LimitNOFILE=infinity
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
}

write_caddy_config() {
  local tls_line=""
  local caddy_auth_hash
  if [[ -n "${EMAIL}" ]]; then
    tls_line="tls ${EMAIL}"
  fi
  caddy_auth_hash="$(caddy hash-password --plaintext "${SUB_AUTH_PASSWORD}")"

  install -d -m 0755 /etc/caddy/conf.d
  if [[ -f /etc/caddy/Caddyfile ]]; then
    cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak.$(date +%Y%m%d%H%M%S)"
  else
    touch /etc/caddy/Caddyfile
  fi

  if ! grep -q '^import /etc/caddy/conf.d/\*.caddy$' /etc/caddy/Caddyfile; then
    printf '\nimport /etc/caddy/conf.d/*.caddy\n' >> /etc/caddy/Caddyfile
  fi

  if [[ "${VPN_DOMAIN}" == "${SUB_DOMAIN}" ]]; then
    cat >/etc/caddy/conf.d/vpn-deploy.caddy <<EOF
${VPN_DOMAIN} {
  ${tls_line}
  encode zstd gzip

  @vpn_ws path ${WS_PATH}
  handle @vpn_ws {
    reverse_proxy 127.0.0.1:10000
  }

  @subscription path ${SUB_PATH}
  handle @subscription {
    basic_auth {
      ${SUB_AUTH_USER} ${caddy_auth_hash}
    }
    root * /opt/shadowrocket-sub
    rewrite * /shadowrocket.conf
    file_server
  }

  @server_subscription path ${SUB_PATH}/server
  handle @server_subscription {
    basic_auth {
      ${SUB_AUTH_USER} ${caddy_auth_hash}
    }
    root * /opt/shadowrocket-sub
    rewrite * /trojan-uri.txt
    file_server
  }

  @clash_subscription path ${SUB_PATH}/clash
  handle @clash_subscription {
    basic_auth {
      ${SUB_AUTH_USER} ${caddy_auth_hash}
    }
    root * /opt/shadowrocket-sub
    rewrite * /clash-meta.yaml
    file_server
  }

  @sing_box_subscription path ${SUB_PATH}/sing-box
  handle @sing_box_subscription {
    basic_auth {
      ${SUB_AUTH_USER} ${caddy_auth_hash}
    }
    root * /opt/shadowrocket-sub
    rewrite * /sing-box-client.json
    file_server
  }

  handle {
    respond "not found" 404
  }
}
EOF
  else
    cat >/etc/caddy/conf.d/vpn-deploy.caddy <<EOF
${VPN_DOMAIN} {
  ${tls_line}
  encode zstd gzip

  @vpn_ws path ${WS_PATH}
  handle @vpn_ws {
    reverse_proxy 127.0.0.1:10000
  }

  handle {
    respond "ok" 200
  }
}

${SUB_DOMAIN} {
  ${tls_line}
  encode zstd gzip

  @subscription path ${SUB_PATH}
  handle @subscription {
    basic_auth {
      ${SUB_AUTH_USER} ${caddy_auth_hash}
    }
    root * /opt/shadowrocket-sub
    rewrite * /shadowrocket.conf
    file_server
  }

  @server_subscription path ${SUB_PATH}/server
  handle @server_subscription {
    basic_auth {
      ${SUB_AUTH_USER} ${caddy_auth_hash}
    }
    root * /opt/shadowrocket-sub
    rewrite * /trojan-uri.txt
    file_server
  }

  @clash_subscription path ${SUB_PATH}/clash
  handle @clash_subscription {
    basic_auth {
      ${SUB_AUTH_USER} ${caddy_auth_hash}
    }
    root * /opt/shadowrocket-sub
    rewrite * /clash-meta.yaml
    file_server
  }

  @sing_box_subscription path ${SUB_PATH}/sing-box
  handle @sing_box_subscription {
    basic_auth {
      ${SUB_AUTH_USER} ${caddy_auth_hash}
    }
    root * /opt/shadowrocket-sub
    rewrite * /sing-box-client.json
    file_server
  }

  handle {
    respond "not found" 404
  }
}
EOF
  fi
}

write_shadowrocket_subscription() {
  install -d -m 0755 /opt/shadowrocket-sub
  local encoded_password encoded_path encoded_name trojan_uri rules_source
  encoded_password="$(urlencode "${TROJAN_PASSWORD}")"
  encoded_path="$(urlencode "${WS_PATH}")"
  encoded_name="$(urlencode "${NODE_NAME}")"
  trojan_uri="trojan://${encoded_password}@${VPN_DOMAIN}:443?security=tls&sni=${VPN_DOMAIN}&type=ws&host=${VPN_DOMAIN}&path=${encoded_path}#${encoded_name}"
  rules_source="${RULES_FILE}"
  if [[ -z "${rules_source}" && -f "${SCRIPT_DIR}/shadowrocket-rules.conf" ]]; then
    rules_source="${SCRIPT_DIR}/shadowrocket-rules.conf"
  fi

  cat >/opt/shadowrocket-sub/shadowrocket.conf <<EOF
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

  if [[ -n "${rules_source}" ]]; then
    [[ -f "${rules_source}" ]] || die "Rules file not found: ${rules_source}"
    cat "${rules_source}" >> /opt/shadowrocket-sub/shadowrocket.conf
  else
    cat >>/opt/shadowrocket-sub/shadowrocket.conf <<'EOF'
DOMAIN-SUFFIX,local,DIRECT
IP-CIDR,10.0.0.0/8,DIRECT
IP-CIDR,172.16.0.0/12,DIRECT
IP-CIDR,192.168.0.0/16,DIRECT
DOMAIN-SUFFIX,cn,DIRECT
DOMAIN-SUFFIX,openai.com,PROXY
DOMAIN-SUFFIX,chatgpt.com,PROXY
DOMAIN-SUFFIX,github.com,PROXY
DOMAIN-SUFFIX,google.com,PROXY
DOMAIN-SUFFIX,youtube.com,PROXY
GEOIP,CN,DIRECT
FINAL,PROXY
EOF
  fi

  cat >>/opt/shadowrocket-sub/shadowrocket.conf <<EOF
[Host]
localhost = 127.0.0.1
EOF

  cat >/opt/shadowrocket-sub/trojan-uri.txt <<EOF
${trojan_uri}
EOF

  cat >/opt/shadowrocket-sub/clash-meta.yaml <<EOF
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

  python3 - "${VPN_DOMAIN}" "${NODE_NAME}" "${TROJAN_PASSWORD}" "${WS_PATH}" >/opt/shadowrocket-sub/sing-box-client.json <<'PY'
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

  chmod 0644 /opt/shadowrocket-sub/shadowrocket.conf /opt/shadowrocket-sub/trojan-uri.txt /opt/shadowrocket-sub/clash-meta.yaml /opt/shadowrocket-sub/sing-box-client.json
}

write_secret_summary() {
  local subscription_url node_subscription_url clash_meta_url sing_box_client_url
  local encoded_auth_user encoded_auth_password
  encoded_auth_user="$(urlencode "${SUB_AUTH_USER}")"
  encoded_auth_password="$(urlencode "${SUB_AUTH_PASSWORD}")"
  subscription_url="https://${encoded_auth_user}:${encoded_auth_password}@${SUB_DOMAIN}${SUB_PATH}"
  node_subscription_url="https://${encoded_auth_user}:${encoded_auth_password}@${SUB_DOMAIN}${SUB_PATH}/server"
  clash_meta_url="https://${encoded_auth_user}:${encoded_auth_password}@${SUB_DOMAIN}${SUB_PATH}/clash"
  sing_box_client_url="https://${encoded_auth_user}:${encoded_auth_password}@${SUB_DOMAIN}${SUB_PATH}/sing-box"
  : >/root/vpn-deploy.env
  write_env_line VPN_DOMAIN "${VPN_DOMAIN}"
  write_env_line SUB_DOMAIN "${SUB_DOMAIN}"
  write_env_line NODE_NAME "${NODE_NAME}"
  write_env_line ACME_EMAIL "${EMAIL}"
  write_env_line WEB_SERVER "${WEB_SERVER}"
  write_env_line TROJAN_PASSWORD "${TROJAN_PASSWORD}"
  write_env_line WS_PATH "${WS_PATH}"
  write_env_line SUB_PATH "${SUB_PATH}"
  write_env_line SUB_AUTH_USER "${SUB_AUTH_USER}"
  write_env_line SUB_AUTH_PASSWORD "${SUB_AUTH_PASSWORD}"
  write_env_line SUBSCRIPTION_URL "${subscription_url}"
  write_env_line SERVER_SUBSCRIPTION_URL "${node_subscription_url}"
  write_env_line NODE_SUBSCRIPTION_URL "${node_subscription_url}"
  write_env_line CLASH_META_URL "${clash_meta_url}"
  write_env_line SING_BOX_CLIENT_URL "${sing_box_client_url}"
  write_env_line TROJAN_URI_FILE /opt/shadowrocket-sub/trojan-uri.txt
  write_env_line SHADOWROCKET_CONF /opt/shadowrocket-sub/shadowrocket.conf
  write_env_line CLASH_META_CONF /opt/shadowrocket-sub/clash-meta.yaml
  write_env_line SING_BOX_CLIENT_CONF /opt/shadowrocket-sub/sing-box-client.json
  chmod 0600 /root/vpn-deploy.env
}

configure_firewall() {
  [[ "${SKIP_UFW}" == "0" ]] || return 0
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "${SSH_PORT}/tcp"
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable
}

start_services() {
  sing-box check -c /etc/sing-box/config.json
  systemctl daemon-reload
  systemctl enable --now sing-box
  if [[ "${WEB_SERVER}" == "caddy" ]]; then
    caddy validate --config /etc/caddy/Caddyfile
    systemctl enable --now caddy
    systemctl reload caddy
  elif [[ "${WEB_SERVER}" == "nginx" ]] && command -v nginx >/dev/null 2>&1; then
    nginx -t || true
  fi
}

main() {
  install_base_packages
  install_sing_box
  if [[ "${WEB_SERVER}" == "caddy" ]]; then
    install_caddy
  fi
  write_sing_box_config
  write_systemd_unit
  write_shadowrocket_subscription
  if [[ "${WEB_SERVER}" == "caddy" ]]; then
    write_caddy_config
  elif [[ "${WEB_SERVER}" == "nginx" ]]; then
    write_nginx_config_draft
  fi
  write_secret_summary
  configure_firewall
  start_services

  cat <<EOF

Self-hosted VPN deployment complete.

Subscription URL:
  https://${SUB_DOMAIN}${SUB_PATH}

Shadowrocket node domain:
  ${VPN_DOMAIN}

Secret summary:
  /root/vpn-deploy.env

Quick checks:
  systemctl status sing-box --no-pager
  sing-box check -c /etc/sing-box/config.json
  curl -I https://${SUB_DOMAIN}${SUB_PATH}
EOF
  if [[ "${WEB_SERVER}" == "nginx" ]]; then
    cat <<'EOF'

Nginx mode:
  Review /root/vpn-deploy-nginx.conf, install certificates for both subdomains,
  then enable it in your existing Nginx config and reload Nginx.
EOF
  elif [[ "${WEB_SERVER}" == "none" ]]; then
    cat <<'EOF'

Web-server mode is none:
  sing-box and subscription files were generated, but no public HTTPS routing
  was installed. Add your own TLS reverse proxy before importing Shadowrocket.
EOF
  fi
}

main "$@"
