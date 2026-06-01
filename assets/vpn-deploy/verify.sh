#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-/root/vpn-deploy.env}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

check_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

[[ -f "${ENV_FILE}" ]] || die "Cannot find ${ENV_FILE}"
# shellcheck disable=SC1090
. "${ENV_FILE}"

check_cmd curl
check_cmd systemctl
check_cmd sing-box

echo "== Domains =="
echo "VPN domain: ${VPN_DOMAIN}"
echo "Subscription domain: ${SUB_DOMAIN}"
echo "Subscription URL: ${SUBSCRIPTION_URL}"
echo "Web server mode: ${WEB_SERVER:-caddy}"

echo
echo "== DNS resolution =="
getent ahosts "${VPN_DOMAIN}" | head -n 3 || true
getent ahosts "${SUB_DOMAIN}" | head -n 3 || true

echo
echo "== sing-box config =="
sing-box check -c /etc/sing-box/config.json

echo
echo "== systemd services =="
systemctl is-active --quiet sing-box && echo "sing-box: active" || die "sing-box is not active"
case "${WEB_SERVER:-caddy}" in
  caddy)
    systemctl is-active --quiet caddy && echo "caddy: active" || die "caddy is not active"
    ;;
  nginx)
    if systemctl is-active --quiet nginx; then
      echo "nginx: active"
    else
      echo "nginx: not active or not managed by systemd"
    fi
    ;;
  none)
    echo "web server: none"
    ;;
esac

echo
echo "== HTTPS subscription =="
if curl -fsSI "${SUBSCRIPTION_URL}" | sed -n '1,8p'; then
  true
elif [[ "${WEB_SERVER:-caddy}" == "caddy" ]]; then
  die "Subscription URL is not reachable"
else
  echo "Subscription URL is not reachable yet. Enable your HTTPS reverse proxy first."
fi

echo
echo "== Local subscription content =="
test -s /opt/shadowrocket-sub/shadowrocket.conf || die "Missing /opt/shadowrocket-sub/shadowrocket.conf"
sed -n '1,40p' /opt/shadowrocket-sub/shadowrocket.conf

echo
echo "== Firewall =="
if command -v ufw >/dev/null 2>&1; then
  ufw status verbose || true
else
  echo "ufw not installed"
fi

echo
echo "Verification complete."
