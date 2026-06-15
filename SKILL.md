---
name: vpn-deploy
description: Deploy, harden, diagnose, and maintain legal self-hosted VPN/access services for Shadowrocket or similar clients. Use when the user asks to set up sing-box, Trojan/VLESS/Reality/WebSocket/TLS, Shadowrocket subscriptions, routing rules, DNS split routing, Nginx/Caddy reverse proxy, Let's Encrypt certificates, server firewall exposure, subscription privacy, or VPS network access troubleshooting. Do not use for residential IP impersonation, platform risk bypass, stealth abuse, spam, credential theft, or evading law enforcement.
---

# VPN Deploy

## Operating Boundary

Build legal, self-owned access services with conservative security defaults. Refuse requests to impersonate residential IPs, bypass platform risk controls, hide abuse, or promise undetectability. Offer lawful alternatives: clean VPS line selection, IP reputation checks, ASN transparency, TLS hygiene, private subscription URLs, and clear client-side routing.

Prefer `sing-box` for the server core and Trojan over TLS/WebSocket behind Nginx or Caddy when compatibility matters. Treat Shadowrocket as one client output, not the only output: also provide a generic node URI, Clash/Mihomo YAML, and sing-box client JSON when users need Android/Windows compatibility.

## Workflow

1. Gather server facts before editing:
   - SSH alias or `user@host`, SSH port, sudo availability, OS version.
   - Public IP, domain/subdomain, DNS proxy status, web server already present.
   - Whether port `443` is already owned by Nginx, Caddy, another proxy, or the VPN daemon.

2. Choose a safe architecture:
   - If an existing website/Nginx owns `443`, bind `sing-box` to `127.0.0.1` and reverse-proxy WebSocket traffic.
   - When Nginx already serves websites, add a separate `server_name` block for the VPN subdomain; do not edit existing site files unless the user explicitly asks.
   - Use webroot ACME (`certbot certonly --webroot`) for that new block instead of `certbot --nginx` when avoiding changes to existing websites matters.
   - If no web server exists, Caddy is acceptable for automatic TLS and static subscription hosting.
   - Use a dedicated subdomain like `vpn.example.com`; keep Cloudflare DNS as DNS-only for non-Cloudflare-compatible proxy protocols.
   - If no branded DNS record exists and the user wants immediate deployment, an auto-resolving name such as `<label>.<ip>.sslip.io` can be used as a temporary dedicated subdomain. Clearly note how to migrate to the user's own DNS later.

3. Generate secrets:
   - Strong Trojan password.
   - Random WebSocket path.
   - Random subscription path.
   - HTTP Basic Auth username/password for every subscription endpoint.
   - Store generated values and final URL names in a root-only env file such as `/root/vpn-deploy.env`; write shell-safe values so names with spaces do not break later `source`.
   - Include `SUBSCRIPTION_URL`, `SERVER_SUBSCRIPTION_URL`/`NODE_SUBSCRIPTION_URL`, `CLASH_META_URL`, and `SING_BOX_CLIENT_URL` when those outputs exist.

4. Deploy server:
   - Install `sing-box`.
   - Create `/etc/sing-box/config.json`.
   - Create a systemd service and enable restart on boot.
   - Configure Nginx/Caddy for TLS, WebSocket proxying, subscription hosting, and Basic Auth.
   - Open only SSH, HTTP/80, and HTTPS/443 unless the existing environment requires otherwise.

5. Generate client outputs:
   - Full remote config: `[General]`, `[Proxy]`, `[Proxy Group]`, `[Rule]`, optional `[Host]`.
   - Generic node subscription: a single `trojan://...` URI for Shadowrocket's "Server Subscription" flow and clients such as v2rayN, NekoRay, v2rayNG, and NekoBox.
   - Clash/Mihomo YAML for common Android/Windows Clash-family clients.
   - sing-box client JSON for native sing-box clients.
   - Explain clearly that node subscriptions do not carry routing rules; full config, Clash/Mihomo, and sing-box configs can carry rules.

6. Validate from both server and public network:
   - `sing-box check -c /etc/sing-box/config.json`
   - `systemctl status sing-box`
   - `curl -I` against clean subscription URLs without credentials: expect `401`.
   - `curl -u user:pass` against full config: expect `200` and `[Rule]`.
   - `curl -u user:pass` against `/server`: expect `200` and `trojan://`.
   - `curl -u user:pass` against `/clash`: expect `200` and `proxies:`.
   - `curl -u user:pass` against `/sing-box`: expect `200` and valid JSON.
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

For Android/Windows, point users to:

- `NODE_SUBSCRIPTION_URL`: generic Trojan node subscription for v2rayN/NekoRay/v2rayNG/NekoBox style clients.
- `CLASH_META_URL`: Clash Meta/Mihomo YAML.
- `SING_BOX_CLIENT_URL`: sing-box client JSON.
