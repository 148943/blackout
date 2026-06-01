# Config Profiles

Blackout renders Xray, Nginx, and share-link templates from profile directories under `/opt/blackout/configs` after installation.

## Commands

```bash
blackout config list
blackout config current
blackout config switch PROFILE
```

## Profile Layout

Each profile directory contains:

```text
xray.conf
nginx.conf
share.template
```

Templates use Blackout placeholders such as `{{DOMAIN}}`, `{{WS_PATH}}`, `{{XRAY_API_PORT}}`, `{{UUID}}`, and `{{USERNAME}}`.

## Default Profile

The shipped profile is `vless-ws-nginx`.

- Xray listens on a Unix socket at `/dev/shm/blackout-vless.sock`.
- Nginx terminates TLS on port `443` and proxies WebSocket traffic to the Xray socket.
- HTTP on port `80` redirects to HTTPS, with an ACME challenge location present in the Nginx template.
- The local Xray API listens on `127.0.0.1` using the configured API port, defaulting to `60001`.
- Xray `HandlerService` and `StatsService` are enabled for runtime user management and stats.

## Switching Profiles

```bash
blackout config switch vless-ws-nginx
```

The switch command requires a stored domain setting. It renders the profile with the stored domain, WebSocket path, and Xray API port; validates Xray JSON with `jq`; installs and tests the Nginx site; writes the Xray config; writes `/etc/blackout/share.template`; stores the active profile; restarts Xray; and reloads Nginx.

The implementation validates Nginx and restores the previous Nginx site if `nginx -t` fails.

