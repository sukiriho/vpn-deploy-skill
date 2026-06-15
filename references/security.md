# Security and Compliance Defaults

## Refusal Boundary

Do not help with:

- Residential IP impersonation.
- Claims or designs for "100% undetectable" traffic.
- Platform fraud, risk-control bypass, spam, credential theft, or hiding abuse.
- Instructions to evade law enforcement or provider enforcement.

Offer safer alternatives:

- Use a clean, reputable VPS provider and line.
- Check ASN, IP reputation, and blacklist status.
- Rotate exposed subscription paths and credentials after accidental sharing.
- Keep logs minimal but sufficient for debugging.

## Subscription Privacy

- Never expose subscription files publicly.
- Use both a high-entropy path and HTTP Basic Auth.
- Treat full URLs containing embedded Basic Auth as secrets. HTTPS encrypts them in transit, but anyone with the full URL can fetch the subscription.
- Keep old paths returning `404` after rotation.
- Verify with clean unauthenticated URLs; URLs with embedded credentials will return `200` because they are already authenticated.
- Avoid pasting secrets in final replies; show a command to retrieve them from the server.

## Server Hardening

- Restrict `sing-box` to loopback when behind Nginx/Caddy.
- Open only SSH, HTTP/80, and HTTPS/443.
- Keep SSH key auth; recommend disabling password auth after confirming access.
- Enable systemd restart.
- Keep TLS certificates automated through Let's Encrypt.
- Run `sing-box check` before restart.
