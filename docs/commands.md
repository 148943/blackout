# Blackout Command Reference

Run commands as root unless the command is explicitly read-only.

## Top-level

```bash
blackout
blackout menu
blackout help
blackout --help
blackout -h
```

- `blackout` or `blackout menu`: opens the interactive control panel menu.
- `blackout help`, `blackout --help`, `blackout -h`: prints command usage.

The interactive menu includes Users, Xray, Certificates, Config, API, and Update check.

## Users

```bash
blackout user add
blackout user remove USERNAME
blackout user modify USERNAME
blackout user lock USERNAME
blackout user unlock USERNAME
blackout user list
blackout user online
blackout user online SECONDS
blackout user link USERNAME
blackout user expire
```

- `add`: prompts for username and duration; creates a SQLite row and adds the user to Xray through the local API.
- `remove USERNAME`: removes the user from Xray runtime state, then deletes the SQLite row.
- `modify USERNAME`: prompts for a new duration, then updates SQLite. It does not rename the user or change the UUID.
- `lock USERNAME`: removes the user from Xray runtime state and marks the SQLite row `locked`.
- `unlock USERNAME`: adds the user back to Xray runtime state and marks the row `active` if it has not expired.
- `list`: prints users from SQLite with username, status, and expiry timestamp.
- `online`: samples Xray stats and prints only users whose traffic increased during the sample window.
- `online SECONDS`: uses a custom numeric sample window instead of the 5 second default.
- `link USERNAME`: renders the active user's client link from the current share template.
- `expire`: removes expired active users from Xray runtime state and marks them `expired`.

Usernames must start with an alphanumeric character and may contain letters, numbers, `.`, `_`, and `-`.

## Xray Core

```bash
blackout xray install [VERSION|latest]
blackout xray update
blackout xray version VERSION
blackout xray current
```

- `install [VERSION|latest]`: installs the requested Xray-core version. If no version is passed, it installs `latest`.
- `update`: installs the latest Xray-core release.
- `version VERSION`: installs a specific Xray-core release tag.
- `current`: runs `xray version`.

Xray releases are downloaded from official `XTLS/Xray-core` GitHub release ZIP assets. Supported architecture mappings include `x86_64`/`amd64`, `aarch64`/`arm64`, and `armv7l`/`armhf`. Xray core install/update commands restart the Xray service unless test overrides are set.

## Certificates

```bash
blackout cert issue EMAIL [DOMAIN]
blackout cert renew
blackout cert change-domain DOMAIN
blackout cert status
```

- `issue EMAIL [DOMAIN]`: installs `acme.sh` if needed, issues a certificate, installs it into `/etc/blackout/ssl`, stores the domain setting, and reloads Nginx when possible. Normal domains use standalone HTTP validation. Wildcard domains use Cloudflare DNS validation and issue both the base domain and wildcard name.
- `renew`: force-renews the stored domain certificate and reinstalls the cert/key. Wildcard renewals use the stored Cloudflare API token from `/etc/blackout/blackout.env`.
- `change-domain DOMAIN`: updates the stored domain setting. For wildcard domains, it also issues the wildcard certificate, re-renders the active config, and reloads services.
- `status`: prints the stored domain and whether the fullchain and private key files exist.

Standalone ACME stops Nginx during issue and renew operations, then starts it again. Wildcard ACME uses Cloudflare DNS validation and needs `BLACKOUT_CF_TOKEN` available during first issue or change-domain.

## Config Profiles

```bash
blackout config list
blackout config switch PROFILE
blackout config current
blackout config ws-path /newpath
blackout config reload
```

- `list`: lists profile directories under the configured Blackout config directory.
- `switch PROFILE`: renders the selected profile, validates Xray JSON with `jq`, installs the Nginx site, runs `nginx -t`, writes the active Xray config and share template, stores profile settings, restarts Xray, and reloads Nginx.
- `current`: prints the stored active profile, defaulting to `default`.
- `ws-path /newpath`: validates and stores the WebSocket path, then reapplies the current profile. This restarts Xray and reloads Nginx.
- `reload`: reapplies the current profile with the stored settings. This restarts Xray and reloads Nginx.

The shipped profile is `default`.

## Blackout Updates

```bash
blackout update check
blackout update
```

- `update check`: read-only. Prints the installed Blackout version, remote branch commit, and status such as latest, update available, or unknown installed version. It does not modify files.
- `update`: updates Blackout scripts and the shipped `/opt/blackout/configs/default` profile from the configured repository and branch, then records the installed commit in `/etc/blackout/blackout.env`. It does not update Xray core or custom config folders.

## User API

The HTTP user API is controlled by `blackout api` commands and backed by systemd.

```bash
blackout api enable
blackout api disable
blackout api status
blackout api token
systemctl status blackout-api
journalctl -u blackout-api -n 100 --no-pager
```

- `enable`: installs the current unit, ensures a token exists, and enables/starts `blackout-api`.
- `disable`: disables and stops `blackout-api`.
- `status`: prints systemd status for the API service.
- `token`: rotates the bearer token, revoking the old token.

See [User API](api.md) for endpoints and curl examples.
