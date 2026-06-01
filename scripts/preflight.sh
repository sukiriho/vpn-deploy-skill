#!/usr/bin/env bash
set -euo pipefail

echo "== system =="
uname -a || true
cat /etc/os-release 2>/dev/null || true

echo
echo "== public ip =="
curl -fsSL --max-time 8 https://api.ipify.org || true
echo

echo
echo "== listeners =="
ss -ltnp 2>/dev/null | sed -n '1,80p' || true

echo
echo "== web servers =="
systemctl is-active nginx 2>/dev/null || true
systemctl is-active caddy 2>/dev/null || true

echo
echo "== sing-box =="
command -v sing-box || true
systemctl is-active sing-box 2>/dev/null || true

echo
echo "== firewall =="
ufw status 2>/dev/null || true

echo
echo "== certificates =="
find /etc/letsencrypt/live -maxdepth 2 -name fullchain.pem -print 2>/dev/null || true
