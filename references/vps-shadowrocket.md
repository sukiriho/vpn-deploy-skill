# VPS / Shadowrocket Deployment Notes

Use this pattern when a VPS already has Nginx or a website on `443`.

## Recommended Topology

- DNS: `vpn.example.com` points to the VPS public IP; Cloudflare-style records should be DNS-only unless the chosen protocol is explicitly compatible with CDN proxying.
- Nginx owns ports `80/443`.
- `sing-box` listens only on loopback, for example `127.0.0.1:10000`.
- Nginx proxies one random WebSocket path to `sing-box`.
- Nginx serves subscription files from `/opt/shadowrocket-sub`.
- Every subscription location uses HTTP Basic Auth.
- When existing websites are present, create a new Nginx site for the VPN `server_name`; avoid editing existing site files. Use a webroot ACME challenge for the new domain to avoid `certbot --nginx` rewriting other sites.
- If the user's desired `vpn.example.com` does not resolve yet and they want an immediate working deployment, use an auto-DNS fallback such as `vpn.<ip>.sslip.io` and tell them how to migrate later.

## Files

- `/etc/sing-box/config.json`
- `/etc/systemd/system/sing-box.service`
- `/etc/nginx/sites-available/<domain>`
- `/opt/shadowrocket-sub/shadowrocket.conf`
- `/opt/shadowrocket-sub/trojan-uri.txt`
- `/opt/shadowrocket-sub/clash-meta.yaml`
- `/opt/shadowrocket-sub/sing-box-client.json`
- `/root/vpn-deploy.env`
- `/root/shadowrocket-rules.conf`

## Shadowrocket Import Model

Shadowrocket has two different concepts:

- Server/node subscription: imports node URIs such as `trojan://...`; it does not import `[Rule]`.
- Remote/full config: imports a `.conf` containing `[General]`, `[Proxy]`, `[Proxy Group]`, and `[Rule]`.

When a user says "couldn't fetch server", check whether they pasted a full config URL into the server-subscription field. Provide a `/server` endpoint that returns only the node URI.

## Cross-Client Outputs

The Trojan WebSocket node is not Shadowrocket-only. Generate these endpoints when users ask for Android/Windows or more generic client support:

- `SUBSCRIPTION_URL`: Shadowrocket full config at `${SUB_PATH}`.
- `SERVER_SUBSCRIPTION_URL` and `NODE_SUBSCRIPTION_URL`: raw `trojan://` node URI at `${SUB_PATH}/server`.
- `CLASH_META_URL`: Clash Meta/Mihomo YAML at `${SUB_PATH}/clash`.
- `SING_BOX_CLIENT_URL`: sing-box client JSON at `${SUB_PATH}/sing-box`.

Keep all four behind the same Basic Auth file and high-entropy subscription path. Save the final URL variables in `/root/vpn-deploy.env`; quote or escape env values so labels with spaces do not break shell sourcing.

## Verification Snippets

Use clean URLs without embedded credentials when checking access control:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://vpn.example.com/sub/random
curl -s -u "$SUB_AUTH_USER:$SUB_AUTH_PASSWORD" -o /tmp/sr.conf -w '%{http_code}\n' https://vpn.example.com/sub/random
curl -s -u "$SUB_AUTH_USER:$SUB_AUTH_PASSWORD" https://vpn.example.com/sub/random/server
curl -s -u "$SUB_AUTH_USER:$SUB_AUTH_PASSWORD" https://vpn.example.com/sub/random/clash
curl -s -u "$SUB_AUTH_USER:$SUB_AUTH_PASSWORD" https://vpn.example.com/sub/random/sing-box
```

Expected:

- Unauthenticated subscription endpoints: `401`.
- Authenticated full config: `200` and contains `[Rule]`.
- Authenticated server endpoint: `200` and starts with `trojan://`.
- Authenticated Clash endpoint: `200` and contains `proxies:`.
- Authenticated sing-box endpoint: `200` and valid JSON.

## Common Failure Modes

- DNS proxied through a CDN that does not pass the protocol as expected.
- Port `443` conflict between Nginx/Caddy and `sing-box`.
- Shadowrocket field mismatch: full config URL pasted into server-subscription UI.
- Public subscription path without Basic Auth.
- Old subscription URL still live after rotation.
- Rules file ends with something other than `FINAL,PROXY`.
