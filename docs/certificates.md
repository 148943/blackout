# Certificates

Blackout uses `acme.sh` for TLS certificates. Normal domains use standalone HTTP validation. Wildcard domains use Cloudflare DNS validation.

Certificates are installed into:

```text
/etc/blackout/ssl/fullchain.pem
/etc/blackout/ssl/privkey.pem
```

## Commands

```bash
blackout cert issue EMAIL [DOMAIN]
blackout cert renew
blackout cert change-domain DOMAIN
blackout cert status
```

## Prerequisites

- The domain's `A` record points to the VPS.
- Port `80` is reachable from the internet.
- Port `80` is not occupied by another unmanaged service during issuance.
- Wildcard domains require a Cloudflare API token with zone read and DNS edit permissions.
- The command is run as root.

## Issue

```bash
blackout cert issue admin@example.com example.com
```

`issue` installs `acme.sh` if needed, stops Nginx, runs standalone HTTP validation, installs the certificate and private key into `/etc/blackout/ssl`, starts Nginx, stores the domain setting, and reloads Nginx when possible.

If `acme.sh` reports that the domain is unchanged and renewal is not due, Blackout installs the existing `acme.sh` certificate instead of forcing a renewal. This makes installer retries safe without consuming unnecessary CA rate limit.

If `DOMAIN` is omitted, Blackout uses the stored domain setting.

For wildcard domains, pass the wildcard name:

```bash
BLACKOUT_CF_TOKEN=cloudflare-token blackout cert issue admin@example.com '*.new.example.com'
```

Blackout derives the base domain, asks Cloudflare for the matching zone ID using the token, and issues one certificate for both `new.example.com` and `*.new.example.com`. The token is stored in `/etc/blackout/blackout.env` with mode `0600`; the zone ID is resolved again whenever wildcard certificates are issued or renewed.

## Renew

```bash
blackout cert renew
```

`renew` uses the stored domain setting, force-renews with `acme.sh`, reinstalls the cert/key, and reloads Nginx when possible. Normal domains stop Nginx during standalone validation. Wildcard domains use Cloudflare DNS validation and do not need port `80`.

## Change Domain

```bash
blackout cert change-domain example.net
blackout cert issue admin@example.com example.net
blackout config switch vless-ws-nginx
```

For normal domains, `change-domain` updates the stored domain setting. Issue a certificate for the new domain afterward, then switch or re-render the active profile so generated configs and links use the new value.

For wildcard domains, use:

```bash
BLACKOUT_CF_TOKEN=cloudflare-token blackout cert change-domain '*.new.example.com'
```

Blackout issues and installs the wildcard certificate, stores the new domain, re-renders the active config, and reloads services.

## Status

```bash
blackout cert status
```

`status` prints the stored domain and reports whether the fullchain and private key files are present.
