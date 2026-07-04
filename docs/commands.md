# Blackout Command Reference

Run commands as root unless the command is explicitly read-only.

## Top-level

```bash
blackout
blackout menu
menu
blackout status
blackout help
blackout --help
blackout -h
```

- `blackout` or `blackout menu`: opens the full-screen administration TUI.
- `menu`: system-wide shortcut for `blackout menu`; the installer preserves an existing `/usr/local/bin/menu` owned by another program.
- `blackout status`: checks whether the Blackout stack is usable end to end.
- `blackout help`, `blackout --help`, `blackout -h`: prints command usage.

The TUI includes a dashboard and views for Status, Users, Xray, Certificates, Config, API, and updates. Press `r` to refresh the current status and view data without moving the current selection.

Global keys:

- Up/Down arrows or `k`/`j`: navigate.
- Enter: select the highlighted row or action.
- `r`: refresh immediately.
- `b`, Backspace, or Escape: return to the previous view.
- `?`: show contextual keyboard help.
- `q`: exit.

Blackout uses Gum for enhanced inputs, confirmations, and operation spinners when available. The full interface remains usable through its pure Bash fallback.

`blackout status` checks systemd state and real usability signals: Xray service, Xray API, Nginx service, `nginx -t`, SQLite schema access, active config profile files, and the optional HTTP user API endpoint when it is enabled.

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
blackout user remove-expired
blackout user auto-remove-expired [DAYS]
blackout user expired-retention [DAYS]
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
- `expire`: removes expired active users from Xray runtime state, marks them `expired`, and auto-removes expired rows older than the configured retention.
- `remove-expired`: immediately deletes all users already marked `expired`.
- `auto-remove-expired [DAYS]`: deletes users marked `expired` for at least the configured retention. Pass `DAYS` to override the configured retention for one run.
- `expired-retention [DAYS]`: prints the current auto-remove retention, or stores a new numeric day value. The default is `3`.

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
blackout config reload
```

- `list`: lists profile directories under the configured Blackout config directory.
- `switch PROFILE`: renders the selected profile, validates Xray JSON with `jq`, installs the Nginx site, runs `nginx -t`, writes the active Xray config and share template, stores profile settings, restarts Xray, and reloads Nginx.
- `current`: prints the stored active profile, defaulting to `default`.
- `reload`: reapplies the current profile with the stored settings. This restarts Xray and reloads Nginx.

The shipped profile is `default`. WebSocket paths are written directly in the profile files; edit `xray.conf`, `nginx.conf`, and `share.template`, then run `blackout config reload`.

## Blackout Updates

```bash
blackout update check
blackout update
```

- `update check`: read-only. Prints the installed Blackout version, remote branch commit, and status such as latest, update available, or unknown installed version. It does not modify files.
- `update`: downloads the configured repository and branch, then re-runs the new `install.sh` in reinstall mode so services, config templates, cron, and API service files are refreshed. It reuses the saved domain, ACME email, Cloudflare token, install paths, database path, and API token when available, and only prompts for missing values. The shipped `/opt/blackout/configs/default` profile is overwritten; custom config folders are preserved. An existing Xray core binary is kept; use `blackout xray update` or `blackout xray version VERSION` to change Xray core.

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
