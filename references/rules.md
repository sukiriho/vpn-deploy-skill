# Shadowrocket Rule Strategy

Default policy: China and LAN direct, international services through proxy.

## Order Matters

Put specific proxy rules before broad direct rules. Examples:

- Apple Relay / Siri / Apple Intelligence proxy rules before `DOMAIN-SUFFIX,apple.com,DIRECT`.
- Copilot rules before broad Microsoft direct rules.
- AI and developer domains before generic catch-all rules.
- `GEOIP,CN,DIRECT` near the end.
- `FINAL,PROXY` last.

## Baseline Categories

Direct:

- LAN and private IP ranges.
- `.cn`, `.中国`, and common mainland services.
- Domestic banking, payment, maps, ecommerce, video, CDN, and app-store resources where the user expects local performance.

Proxy:

- AI: OpenAI, ChatGPT, Sora, Anthropic, Claude, Perplexity, Gemini, Poe, Cursor, Windsurf, Codeium.
- Developer: GitHub, GitLab, npm, Docker, GHCR, PyPI, RubyGems.
- Google and YouTube.
- Telegram, X/Twitter, Facebook, Instagram, Threads, WhatsApp, TikTok, Reddit, Discord.
- Netflix, Spotify, SoundCloud, Twitch, Medium, Wikipedia, LinkedIn, Zoom.
- DNS/IP leak test sites.

Reject:

- Keep ad blocking conservative unless the user asks for aggressive blocking.
- Prefer a small set of stable ad domains over large opaque blocklists that may break app flows.

## Merge Rules

When the user provides an old Shadowrocket config:

1. Extract only `[Rule]`.
2. Drop comments and blank lines.
3. Fix continuation mistakes such as:
   - `DOMAIN-SUFFIX,apple-relay.fastly-edge.com`
   - `,PROXY`
4. Preserve `no-resolve` options on IP rules.
5. Deduplicate exact rules.
6. Move `GEOIP,CN,DIRECT` and `FINAL,PROXY` to the end.
7. Count policies and report the result.
