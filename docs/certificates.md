# Certificates

Blackout uses `acme.sh` standalone mode for TLS certificates. Certificates are installed into:

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
- The command is run as root.

## Issue

```bash
blackout cert issue admin@example.com example.com
```

`issue` installs `acme.sh` if needed, stops Nginx, runs standalone HTTP validation, installs the certificate and private key into `/etc/blackout/ssl`, starts Nginx, stores the domain setting, and reloads Nginx when possible.

If `DOMAIN` is omitted, Blackout uses the stored domain setting.

## Renew

```bash
blackout cert renew
```

`renew` uses the stored domain setting, stops Nginx, force-renews with `acme.sh`, reinstalls the cert/key, starts Nginx, and reloads Nginx when possible.

## Change Domain

```bash
blackout cert change-domain example.net
blackout cert issue admin@example.com example.net
blackout config switch vless-ws-nginx
```

`change-domain` currently updates the stored domain setting only. Issue a certificate for the new domain afterward, then switch or re-render the active profile so generated configs and links use the new value.

## Status

```bash
blackout cert status
```

`status` prints the stored domain and reports whether the fullchain and private key files are present.

