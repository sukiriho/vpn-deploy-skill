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
echo "Subscription URL: ${SUBSCRIPTION_URL:-not set}"
echo "Node subscription URL: ${NODE_SUBSCRIPTION_URL:-${SERVER_SUBSCRIPTION_URL:-not set}}"
echo "Clash/Mihomo URL: ${CLASH_META_URL:-not set}"
echo "sing-box client URL: ${SING_BOX_CLIENT_URL:-not set}"
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
echo "== HTTPS subscription access =="
check_subscription_url() {
  local name="$1"
  local url="$2"
  local pattern="$3"
  local clean_url unauth_code auth_tmp auth_code
  if [[ -z "${url}" ]]; then
    echo "${name}: not set"
    return 0
  fi
  if [[ "${url}" != https://*@* ]]; then
    echo "${name}: skipped clean 401 check because URL has no embedded Basic Auth"
    return 0
  fi
  clean_url="${url#https://}"
  clean_url="https://${clean_url#*@}"
  unauth_code="$(curl -k -s -o /dev/null -w '%{http_code}' "${clean_url}" || true)"
  auth_tmp="$(mktemp)"
  auth_code="$(curl -k -s -o "${auth_tmp}" -w '%{http_code}' "${url}" || true)"
  if [[ "${unauth_code}" != "401" ]]; then
    die "${name} unauthenticated check expected 401, got ${unauth_code}"
  fi
  if [[ "${auth_code}" != "200" ]]; then
    die "${name} authenticated check expected 200, got ${auth_code}"
  fi
  if ! grep -Eq "${pattern}" "${auth_tmp}"; then
    die "${name} content did not match expected pattern"
  fi
  rm -f "${auth_tmp}"
  echo "${name}: unauth=401 auth=200 content=ok"
}

check_subscription_url "SUBSCRIPTION_URL" "${SUBSCRIPTION_URL:-}" "\\[Rule\\]"
check_subscription_url "SERVER_SUBSCRIPTION_URL" "${SERVER_SUBSCRIPTION_URL:-}" "^trojan://"
check_subscription_url "CLASH_META_URL" "${CLASH_META_URL:-}" "^proxies:"
check_subscription_url "SING_BOX_CLIENT_URL" "${SING_BOX_CLIENT_URL:-}" "^\\{"

echo
echo "== Local subscription content =="
test -s /opt/shadowrocket-sub/shadowrocket.conf || die "Missing /opt/shadowrocket-sub/shadowrocket.conf"
test -s /opt/shadowrocket-sub/trojan-uri.txt || die "Missing /opt/shadowrocket-sub/trojan-uri.txt"
test -s /opt/shadowrocket-sub/clash-meta.yaml || die "Missing /opt/shadowrocket-sub/clash-meta.yaml"
test -s /opt/shadowrocket-sub/sing-box-client.json || die "Missing /opt/shadowrocket-sub/sing-box-client.json"
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
