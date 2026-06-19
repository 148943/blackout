# Config Profiles

Blackout renders Xray, Nginx, and share-link templates from profile directories under `/opt/blackout/configs` after installation.

## Commands

```bash
blackout config list
blackout config current
blackout config switch PROFILE
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
- `{{API_NGINX_BLOCK}}`: generated Nginx location for the optional Blackout user API.
- `{{UUID}}` and `{{USERNAME}}`: user link placeholders for `share.template`.

WebSocket paths are not rendered from a placeholder. Write the path manually in `xray.conf`, `nginx.conf`, and `share.template`.

## Share Templates

`share.template` can be either a single raw link or multiple named links. A single-line template is printed as-is for backward compatibility.

For named links, use pairs of non-empty lines:

```text
VLESS WS TLS
vless://{{UUID}}@{{DOMAIN}}:443?type=ws&security=tls&path=/vless&host={{DOMAIN}}#{{USERNAME}}

Clash Meta
vless://{{UUID}}@{{DOMAIN}}:443?type=ws&security=tls&path=/vless&host={{DOMAIN}}#{{USERNAME}}-clash
```

`blackout user link USERNAME` prints each pair as a titled link block. It reads the active profile's `share.template` from the profile directory first, then falls back to the installed `/etc/blackout/share.template`.

## Default Profile

The shipped profile is `default`.

- Xray logs to `/var/log/xray/access.log` and `/var/log/xray/error.log` at `warning` level.
- Xray listens on Unix sockets at `/dev/shm/blackout-vless.sock` and `/dev/shm/blackout-xhttp.sock`.
- Nginx terminates TLS on port `443` and proxies WebSocket traffic on `/vless` and XHTTP traffic on `/xhttp` to the Xray sockets.
- HTTP on port `80` redirects to HTTPS, with an ACME challenge location present in the Nginx template.
- The local Xray API listens on `127.0.0.1` using the configured API port, defaulting to `60001`.
- Xray `HandlerService` and `StatsService` are enabled for runtime user management and stats.

`blackout update` overwrites the shipped `default` profile only. Other folders under `/opt/blackout/configs` are treated as custom profiles and are preserved.

## Switching Profiles

```bash
blackout config switch default
```

The switch command requires a stored domain setting. It renders the profile with the stored domain, Xray API port, TLS certificate paths, and API Nginx block; validates Xray JSON with `jq`; installs and tests the Nginx site; writes the Xray config; writes `/etc/blackout/share.template`; stores the active profile; restarts Xray; and reloads Nginx.

The implementation validates Nginx and restores the previous Nginx site if `nginx -t` fails.

Reload the current profile without changing settings:

```bash
blackout config reload
```

## WebSocket Path

To change the WebSocket path, edit the active profile files manually:

- `xray.conf`: set the VLESS WebSocket `wsSettings.path`.
- `nginx.conf`: update the matching WebSocket `location` and socket `proxy_pass`.
- `share.template`: update the client link path.

Then run:

```bash
blackout config reload
```

Do not use `/blackout-api` or anything below `/blackout-api/` as the WebSocket path; that route is reserved for the optional user API.

## Nginx Placeholders

Custom Nginx profile templates should include these placeholders inside the TLS `server` block:

```nginx
ssl_certificate {{SSL_CERT}};
ssl_certificate_key {{SSL_KEY}};

location = /vless {
    proxy_http_version 1.1;
    proxy_set_header Host {{DOMAIN}};
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_pass http://unix:/dev/shm/blackout-vless.sock:/vless;
}

{{API_NGINX_BLOCK}}
```

`{{API_NGINX_BLOCK}}` renders a `/blackout-api/` proxy to `127.0.0.1:8787` without a trailing slash on `proxy_pass`; the API server expects to receive the `/blackout-api/v1/...` path unchanged.
