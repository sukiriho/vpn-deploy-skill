# VPS / Shadowrocket Deployment Notes

Use this pattern when a VPS already has Nginx or a website on `443`.

## Recommended Topology

- DNS: `vpn.example.com` points to the VPS public IP; Cloudflare-style records should be DNS-only unless the chosen protocol is explicitly compatible with CDN proxying.
- Nginx owns ports `80/443`.
- `sing-box` listens only on loopback, for example `127.0.0.1:10000`.
- Nginx proxies one random WebSocket path to `sing-box`.
- Nginx serves subscription files from `/opt/shadowrocket-sub`.
- Every subscription location uses HTTP Basic Auth.

## Files

- `/etc/sing-box/config.json`
- `/etc/systemd/system/sing-box.service`
- `/etc/nginx/sites-available/<domain>`
- `/opt/shadowrocket-sub/shadowrocket.conf`
- `/opt/shadowrocket-sub/trojan-uri.txt`
- `/root/vpn-deploy.env`
- `/root/shadowrocket-rules.conf`

## Shadowrocket Import Model

Shadowrocket has two different concepts:

- Server/node subscription: imports node URIs such as `trojan://...`; it does not import `[Rule]`.
- Remote/full config: imports a `.conf` containing `[General]`, `[Proxy]`, `[Proxy Group]`, and `[Rule]`.

When a user says "couldn't fetch server", check whether they pasted a full config URL into the server-subscription field. Provide a `/server` endpoint that returns only the node URI.

## Verification Snippets

Use clean URLs without embedded credentials when checking access control:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://vpn.example.com/sub/random
curl -s -u "$SUB_AUTH_USER:$SUB_AUTH_PASSWORD" -o /tmp/sr.conf -w '%{http_code}\n' https://vpn.example.com/sub/random
curl -s -u "$SUB_AUTH_USER:$SUB_AUTH_PASSWORD" https://vpn.example.com/sub/random/server
```

Expected:

- Unauthenticated subscription endpoints: `401`.
- Authenticated full config: `200` and contains `[Rule]`.
- Authenticated server endpoint: `200` and starts with `trojan://`.

## Common Failure Modes

- DNS proxied through a CDN that does not pass the protocol as expected.
- Port `443` conflict between Nginx/Caddy and `sing-box`.
- Shadowrocket field mismatch: full config URL pasted into server-subscription UI.
- Public subscription path without Basic Auth.
- Old subscription URL still live after rotation.
- Rules file ends with something other than `FINAL,PROXY`.
