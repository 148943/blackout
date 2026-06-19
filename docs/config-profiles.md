# Config Profiles

Blackout renders Xray, Nginx, and share-link templates from profile directories under `/opt/blackout/configs` after installation.

## Commands

```bash
blackout config list
blackout config current
blackout config switch PROFILE
blackout config ws-path /newpath
blackout config reload
```

## Profile Layout

Each profile directory contains:

```text
xray.conf
nginx.conf
share.template
```

Templates use Blackout placeholders. If the stored domain is wildcard, `{{DOMAIN}}` renders as the base domain, for example `*.new.example.com` becomes `new.example.com`.

Common placeholders:

- `{{DOMAIN}}`: configured domain, with wildcard prefix removed.
- `{{XRAY_API_PORT}}`: local Xray API port.
- `{{SSL_CERT}}`: installed TLS fullchain path.
- `{{SSL_KEY}}`: installed TLS private key path.
- `{{WS_NGINX_BLOCK}}`: generated Nginx WebSocket location for the configured WebSocket path.
- `{{API_NGINX_BLOCK}}`: generated Nginx location for the optional Blackout user API.
- `{{WS_PATH}}`: configured WebSocket path for Xray JSON and share-link templates.
- `{{UUID}}` and `{{USERNAME}}`: user link placeholders for `share.template`.

Nginx templates should use `{{WS_NGINX_BLOCK}}` instead of placing `{{WS_PATH}}` directly in the Nginx file.

## Share Templates

`share.template` can be either a single raw link or multiple named links. A single-line template is printed as-is for backward compatibility.

For named links, use pairs of non-empty lines:

```text
VLESS WS TLS
vless://{{UUID}}@{{DOMAIN}}:443?type=ws&security=tls&path={{WS_PATH}}&host={{DOMAIN}}#{{USERNAME}}

Clash Meta
vless://{{UUID}}@{{DOMAIN}}:443?type=ws&security=tls&path={{WS_PATH}}&host={{DOMAIN}}#{{USERNAME}}-clash
```

`blackout user link USERNAME` prints each pair as a titled link block. It reads the active profile's `share.template` from the profile directory first, then falls back to the installed `/etc/blackout/share.template`.

## Default Profile

The shipped profile is `default`.

- Xray listens on a Unix socket at `/dev/shm/blackout-vless.sock`.
- Nginx terminates TLS on port `443` and proxies WebSocket traffic to the Xray socket.
- HTTP on port `80` redirects to HTTPS, with an ACME challenge location present in the Nginx template.
- The local Xray API listens on `127.0.0.1` using the configured API port, defaulting to `60001`.
- Xray `HandlerService` and `StatsService` are enabled for runtime user management and stats.

`blackout update` overwrites the shipped `default` profile only. Other folders under `/opt/blackout/configs` are treated as custom profiles and are preserved.

## Switching Profiles

```bash
blackout config switch default
```

The switch command requires a stored domain setting. It renders the profile with the stored domain, WebSocket path, and Xray API port; validates Xray JSON with `jq`; installs and tests the Nginx site; writes the Xray config; writes `/etc/blackout/share.template`; stores the active profile; restarts Xray; and reloads Nginx.

The implementation validates Nginx and restores the previous Nginx site if `nginx -t` fails.

Reload the current profile without changing settings:

```bash
blackout config reload
```

## WebSocket Path

```bash
blackout config ws-path /newpath
```

The WebSocket path may be `/`, or it must start with `/` and may contain letters, numbers, `.`, `_`, `~`, `/`, and `-`. Changing it stores the new `ws_path`, reapplies the current profile, restarts Xray, reloads Nginx, and makes newly generated share links use the new path.

`/blackout-api` and anything below `/blackout-api/` are reserved for the optional user API and cannot be used as the WebSocket path.

## Nginx Placeholders

Custom Nginx profile templates should include these placeholders inside the TLS `server` block:

```nginx
ssl_certificate {{SSL_CERT}};
ssl_certificate_key {{SSL_KEY}};

{{WS_NGINX_BLOCK}}

{{API_NGINX_BLOCK}}
```

`{{API_NGINX_BLOCK}}` renders a `/blackout-api/` proxy to `127.0.0.1:8787` without a trailing slash on `proxy_pass`; the API server expects to receive the `/blackout-api/v1/...` path unchanged.
