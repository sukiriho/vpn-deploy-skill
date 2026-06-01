#!/usr/bin/env bash
set -euo pipefail

VPN_DOMAIN="${1:-}"
SUB_DOMAIN="${2:-}"

echo "== Public IP =="
curl -fsSL https://api.ipify.org || true
echo

echo
echo "== IP info =="
if command -v jq >/dev/null 2>&1; then
  curl -fsSL https://ipinfo.io/json | jq .
else
  curl -fsSL https://ipinfo.io/json || true
  echo
fi

if [[ -n "${VPN_DOMAIN}" || -n "${SUB_DOMAIN}" ]]; then
  echo
  echo "== Domain resolution =="
  if [[ -n "${VPN_DOMAIN}" ]]; then
    echo "${VPN_DOMAIN}:"
    getent ahosts "${VPN_DOMAIN}" | head -n 5 || true
  fi
  if [[ -n "${SUB_DOMAIN}" ]]; then
    echo "${SUB_DOMAIN}:"
    getent ahosts "${SUB_DOMAIN}" | head -n 5 || true
  fi
fi

echo
echo "Note: this check reports the data-center/VPS IP identity. It does not and cannot make a data-center IP appear residential."
