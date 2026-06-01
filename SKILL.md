---
name: vpn-deploy
description: Deploy, harden, diagnose, and maintain legal self-hosted VPN/access services for Shadowrocket or similar clients. Use when the user asks to set up sing-box, Trojan/VLESS/Reality/WebSocket/TLS, Shadowrocket subscriptions, routing rules, DNS split routing, Nginx/Caddy reverse proxy, Let's Encrypt certificates, server firewall exposure, subscription privacy, or VPS network access troubleshooting. Do not use for residential IP impersonation, platform risk bypass, stealth abuse, spam, credential theft, or evading law enforcement.
---

# VPN Deploy

## Operating Boundary

Build legal, self-owned access services with conservative security defaults. Refuse requests to impersonate residential IPs, bypass platform risk controls, hide abuse, or promise undetectability. Offer lawful alternatives: clean VPS line selection, IP reputation checks, ASN transparency, TLS hygiene, private subscription URLs, and clear client-side routing.

Prefer `sing-box` for the server core and Shadowrocket-compatible output. For iOS Shadowrocket, default to Trojan over TLS/WebSocket behind Nginx or Caddy when compatibility matters.

## Workflow

1. Gather server facts before editing:
   - SSH alias or `user@host`, SSH port, sudo availability, OS version.
   - Public IP, domain/subdomain, DNS proxy status, web server already present.
   - Whether port `443` is already owned by Nginx, Caddy, another proxy, or the VPN daemon.

2. Choose a safe architecture:
   - If an existing website/Nginx owns `443`, bind `sing-box` to `127.0.0.1` and reverse-proxy WebSocket traffic.
   - If no web server exists, Caddy is acceptable for automatic TLS and static subscription hosting.
   - Use a dedicated subdomain like `vpn.example.com`; keep Cloudflare DNS as DNS-only for non-Cloudflare-compatible proxy protocols.

3. Generate secrets:
   - Strong Trojan password.
   - Random WebSocket path.
   - Random subscription path.
   - HTTP Basic Auth username/password for every subscription endpoint.
   - Store generated values in a root-only env file such as `/root/vpn-deploy.env`; do not paste secrets in final replies.

4. Deploy server:
   - Install `sing-box`.
   - Create `/etc/sing-box/config.json`.
   - Create a systemd service and enable restart on boot.
   - Configure Nginx/Caddy for TLS, WebSocket proxying, subscription hosting, and Basic Auth.
   - Open only SSH, HTTP/80, and HTTPS/443 unless the existing environment requires otherwise.

5. Generate Shadowrocket outputs:
   - Full remote config: `[General]`, `[Proxy]`, `[Proxy Group]`, `[Rule]`, optional `[Host]`.
   - Server subscription: a single `trojan://...` URI for Shadowrocket's "Server Subscription" flow.
   - Explain clearly that node subscriptions do not carry rules; full config subscriptions do.

6. Validate from both server and public network:
   - `sing-box check -c /etc/sing-box/config.json`
   - `systemctl status sing-box`
   - `curl -I` against clean subscription URLs without credentials: expect `401`.
   - `curl -u user:pass` against full config: expect `200` and `[Rule]`.
   - `curl -u user:pass` against `/server`: expect `200` and `trojan://`.
   - Test WebSocket upgrade or an actual local `sing-box` client when possible.

7. Maintain:
   - Keep a durable rules file, for example `/root/shadowrocket-rules.conf`.
   - Keep a refresh script that regenerates subscription files from secrets and rules.
   - Verify certificate renewal and service restart after reboot.

## Resources

- Read `references/vps-shadowrocket.md` for the VPS/Nginx/Shadowrocket pattern and exact checks.
- Read `references/rules.md` when merging or auditing Shadowrocket routing rules.
- Read `references/security.md` for boundaries and hardening defaults.
- Use `scripts/preflight.sh` as a remote-server inspection helper.
- Use `scripts/merge_shadowrocket_rules.py` to normalize and merge existing Shadowrocket rules with a safer modern prelude.
- Use `assets/vpn-deploy/` as a reusable installer package template when a complete deployment artifact is needed.

## Final Response Style

Report URLs by name, not by secret value, unless the user explicitly asks to reveal them. Prefer:

```bash
ssh <server-alias> 'sudo cat /root/vpn-deploy.env'
```

Say exactly which endpoint goes into which Shadowrocket UI:

- `SERVER_SUBSCRIPTION_URL`: server/node subscription.
- `SUBSCRIPTION_URL`: full config subscription with routing rules.
