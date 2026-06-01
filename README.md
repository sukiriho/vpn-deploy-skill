# vpn-deploy-skill

Codex skill for deploying and maintaining legal self-hosted VPN/access services for Shadowrocket and similar clients.

This skill was designed around a practical `sing-box` + TLS/WebSocket + Nginx/Caddy workflow, with private Shadowrocket subscription output and conservative routing rules.

## About

`vpn-deploy-skill` turns Codex into a practical deployment assistant for self-hosted access infrastructure. It packages the operational checklist, scripts, rule strategy, and safety guardrails needed to deploy a Shadowrocket-compatible service on a VPS without leaking private subscription details.

The default architecture favors maintainability over mystery: `sing-box` handles the access service, Nginx or Caddy handles TLS and subscription hosting, and Shadowrocket receives either a full remote config or a node-only subscription depending on the import flow.

Recommended GitHub About description:

```text
Codex skill for legal self-hosted Shadowrocket VPN deployment with sing-box, TLS/WebSocket, private subscriptions, and routing rules.
```

Recommended topics:

```text
codex-skill sing-box shadowrocket vpn trojan nginx caddy self-hosted routing-rules
```

## What It Does

- Deploys a self-hosted access service on a VPS.
- Generates Shadowrocket-compatible outputs:
  - Full remote config with `[General]`, `[Proxy]`, `[Proxy Group]`, and `[Rule]`.
  - Server subscription endpoint returning a single `trojan://...` URI.
- Supports `sing-box` with Trojan over TLS/WebSocket.
- Works with existing Nginx/Caddy deployments.
- Adds private subscription protection with random paths and HTTP Basic Auth.
- Provides rule merging for "China direct + international proxy" routing.
- Includes validation and troubleshooting steps.

## Safety Boundary

This skill is for lawful self-owned infrastructure only.

It does not support:

- Residential IP impersonation.
- "100% undetectable" traffic claims.
- Platform risk-control bypass.
- Spam, credential theft, fraud, abuse hiding, or law-enforcement evasion.

For reliability, it focuses on clean VPS configuration, TLS hygiene, minimal exposure, private subscriptions, and transparent routing.

## Install

Clone or copy this folder into your Codex skills directory:

```bash
mkdir -p ~/.codex/skills
git clone git@github.com:sukiriho/vpn-deploy-skill.git ~/.codex/skills/vpn-deploy
```

Then invoke it in Codex with:

```text
Use $vpn-deploy to deploy a secure Shadowrocket-compatible VPN on my VPS.
```

## Repository Layout

```text
.
├── SKILL.md
├── agents/
│   └── openai.yaml
├── assets/
│   └── vpn-deploy/
│       ├── install.sh
│       ├── deploy-remote.sh
│       ├── refresh-subscription.sh
│       ├── verify.sh
│       ├── check-ip.sh
│       ├── preflight.sh
│       └── shadowrocket-rules.conf
├── references/
│   ├── rules.md
│   ├── security.md
│   └── vps-shadowrocket.md
└── scripts/
    ├── merge_shadowrocket_rules.py
    └── preflight.sh
```

## Typical Flow

1. Confirm VPS facts:
   - OS version.
   - SSH target and port.
   - Domain/subdomain DNS.
   - Existing web server on ports `80/443`.

2. Deploy:
   - Install `sing-box`.
   - Bind service to loopback when Nginx/Caddy owns `443`.
   - Generate strong Trojan password, WebSocket path, subscription path, and Basic Auth credentials.
   - Write secrets to a root-only env file such as `/root/vpn-deploy.env`.

3. Generate subscriptions:
   - `SUBSCRIPTION_URL`: full Shadowrocket config with rules.
   - `SERVER_SUBSCRIPTION_URL`: node-only server subscription.

4. Verify:
   - Unauthenticated subscription URL returns `401`.
   - Authenticated full config returns `200` and contains `[Rule]`.
   - Authenticated server subscription returns `trojan://...`.
   - `sing-box check` passes.
   - Service restarts correctly after reboot.

## Rule Strategy

Default routing model:

- LAN/private ranges direct.
- Mainland China domains and `GEOIP,CN` direct.
- AI, developer services, Google/YouTube, social, messaging, streaming, and leak-test domains through proxy.
- Conservative ad rejects to avoid breaking apps.
- `FINAL,PROXY` last.

To merge an existing Shadowrocket config:

```bash
python3 scripts/merge_shadowrocket_rules.py /path/to/default.conf -o /tmp/shadowrocket-rules.conf
```

## Shadowrocket Notes

Shadowrocket has two different import concepts:

- Server subscription: imports node URIs such as `trojan://...`.
- Full config / remote config: imports `[General]`, `[Proxy]`, `[Proxy Group]`, and `[Rule]`.

If the server subscription field says it cannot fetch a server, make sure you are using the node-only `SERVER_SUBSCRIPTION_URL`, not the full config URL.

## Secret Handling

Do not commit generated values such as:

- Trojan passwords.
- Basic Auth credentials.
- Real subscription paths.
- Private keys.
- Generated `.env` files.
- Generated `shadowrocket.conf` or `trojan-uri.txt`.

The `.gitignore` blocks common generated secret files, but always scan before committing.
