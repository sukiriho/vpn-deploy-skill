#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Run non-mutating checks before installing the Self-hosted VPN service.

Usage:
  sudo bash preflight.sh --vpn-domain vpn.example.com --sub-domain vpn.example.com [options]

Required:
  --vpn-domain DOMAIN        Domain used by Shadowrocket node traffic.
  --sub-domain DOMAIN        Domain used by the private subscription URL. Can equal --vpn-domain.

Options:
  --ssh-port PORT            SSH port expected to stay open. Default: 22.
  -h, --help                 Show this help.
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

warn() {
  echo "WARN: $*" >&2
}

VPN_DOMAIN=""
SUB_DOMAIN=""
SSH_PORT="22"

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
    --ssh-port)
      SSH_PORT="${2:-22}"
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

[[ -n "${VPN_DOMAIN}" ]] || die "--vpn-domain is required"
[[ -n "${SUB_DOMAIN}" ]] || die "--sub-domain is required"
[[ "${SSH_PORT}" =~ ^[0-9]+$ ]] || die "--ssh-port must be numeric"

echo "== OS =="
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "${PRETTY_NAME:-${ID:-unknown}}"
  case "${ID:-}" in
    ubuntu|debian) ;;
    *) die "Unsupported OS '${ID:-unknown}'. Use Ubuntu 22.04/24.04 or Debian 12." ;;
  esac
else
  die "Missing /etc/os-release"
fi

echo
echo "== Current public IP =="
PUBLIC_IP=""
if command -v curl >/dev/null 2>&1; then
  PUBLIC_IP="$(curl -fsSL --max-time 10 https://api.ipify.org || true)"
  echo "${PUBLIC_IP:-unknown}"
else
  warn "curl is not installed; cannot check public IP"
fi

echo
echo "== DNS =="
resolve_domain() {
  local domain="$1"
  local resolved=""
  if command -v getent >/dev/null 2>&1; then
    resolved="$(getent ahosts "${domain}" | awk '{print $1}' | sort -u | tr '\n' ' ' || true)"
  fi
  echo "${domain}: ${resolved:-not resolved}"
  if [[ -n "${PUBLIC_IP}" && -n "${resolved}" && " ${resolved} " != *" ${PUBLIC_IP} "* ]]; then
    warn "${domain} does not currently resolve to this server public IP (${PUBLIC_IP})"
  fi
}
resolve_domain "${VPN_DOMAIN}"
if [[ "${SUB_DOMAIN}" != "${VPN_DOMAIN}" ]]; then
  resolve_domain "${SUB_DOMAIN}"
else
  echo "single-domain mode: subscription and node share ${VPN_DOMAIN}"
fi

echo
echo "== Port listeners =="
if command -v ss >/dev/null 2>&1; then
  ss -ltnp '( sport = :22 or sport = :80 or sport = :443 )' || true
  if ss -ltnp '( sport = :80 or sport = :443 )' | awk 'NR > 1 {print}' | grep -q .; then
    warn "80/443 already have listeners. Do not run install.sh until you confirm this will not interrupt an existing site."
    warn "If this server already uses Nginx/Apache for the main domain, integrate the subdomain routing there instead of letting Caddy take over."
  fi
else
  warn "ss is not installed; cannot inspect listening ports"
fi

echo
echo "== Existing services =="
for service in nginx apache2 caddy sing-box; do
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files "${service}.service" >/dev/null 2>&1; then
    state="$(systemctl is-active "${service}" 2>/dev/null || true)"
    echo "${service}: ${state:-installed}"
  fi
done

echo
echo "== Firewall hint =="
echo "Installer default keeps only ${SSH_PORT}/tcp, 80/tcp, and 443/tcp open via UFW."
echo "If the provider firewall is separate from UFW, open the same ports in the Nginx/VPS panel."

echo
echo "Preflight complete."
