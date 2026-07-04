# Blackout

Blackout is a Bash management suite for Debian 12 and 13 VPS hosts running Xray-core behind an Nginx reverse proxy. It installs and manages the `default` profile, TLS certificates from `acme.sh`, SQLite-backed users, automated expiry cleanup, Xray API runtime user changes, Xray core updates, and Blackout script updates.

Routine user operations use the local Xray API instead of restarting Xray. State is stored in SQLite at `/var/lib/blackout/blackout.db` after installation.

Fresh installs add `/etc/cron.d/blackout-expire`, which runs `blackout user expire` every 5 minutes. Expired users are auto-removed after 3 days by default; change it with `blackout user expired-retention DAYS`.

More documentation:

- [Command reference](docs/commands.md)
- [Config profiles](docs/config-profiles.md)
- [User management](docs/user-management.md)
- [User API](docs/api.md)
- [Certificates](docs/certificates.md)
- [Troubleshooting](docs/troubleshooting.md)

## Requirements

- Fresh Debian 12 or 13 VPS.
- Root shell or `sudo -i`.
- A domain name with an `A` record pointing to the VPS IPv4 address. Add an `AAAA` record only if IPv6 is configured and reachable.
- Ports `80` and `443` open from the internet.
- `git` access to `https://github.com/148943/blackout.git`.
- For wildcard domains such as `*.new.example.com`, a Cloudflare API token with zone read and DNS edit permissions.

Blackout installs its runtime dependencies during `bash install.sh`: `curl`, `unzip`, `jq`, `sqlite3`, `nginx`, `socat`, `cron`, `ca-certificates`, `git`, `uuid-runtime`, `python3`, `gnupg`, and [Gum](https://github.com/charmbracelet/gum). Gum is installed from Charm's signed Debian repository. If Gum cannot be installed, Blackout keeps a complete pure Bash TUI fallback.

## Fresh Debian 12/13 VPS Install

Run these commands as root on the VPS:

```bash
apt update && apt upgrade -y
apt install -y git curl
git clone https://github.com/148943/blackout.git
cd blackout
bash install.sh
blackout user add
blackout user link USERNAME
```

`bash install.sh` prompts for:

- `Domain`: the domain whose DNS `A` record already points to the VPS.
- `ACME email`: the email address used by `acme.sh`.
- `Cloudflare API token`: shown only when the domain starts with `*.`.

The installer checks Debian 12 or 13, installs packages, initializes SQLite, installs Blackout under `/opt/blackout`, installs the CLI at `/usr/local/bin/blackout`, creates `/usr/local/bin/menu` when that path is available, installs Xray-core, issues a certificate, renders the `default` Xray and Nginx configs, enables Xray and Nginx, and prints `blackout status` at the end. The local `blackout-api` service is installed but disabled by default.

Normal domains use `acme.sh` standalone validation on port `80`. Wildcard domains use Cloudflare DNS validation and automatically request both the base domain and wildcard name, for example `new.example.com` and `*.new.example.com`.

## Administration TUI

Run `blackout`, `blackout menu`, or the installed `menu` shortcut to open the full-screen administration dashboard. It shows stack health, users, the active profile, certificate/API state, and update context. Press `r` to refresh the current status and view data.

```text
↑/↓ or j/k  Navigate
Enter       Select
r           Refresh immediately
b or Esc    Back
?           Contextual help
q           Quit
```

Operations that can remove access, replace configuration, rotate credentials, or disrupt connectivity require confirmation. Long-running commands show a spinner and retain their output in a result panel.

## First User

Create the first user:

```bash
blackout user add
```

The prompt asks for username and duration such as `12h`, `7d`, or `1m`. Blackout stores the user in SQLite, generates a UUID, and adds the VLESS client to every user inbound in the running Xray config through the local Xray API.

Print the client link:

```bash
blackout user link USERNAME
```

The default links include TLS on port `443` and HTTP on port `80` for both WebSocket `/ws` and XHTTP `/xhttp`.

## Common Commands

```bash
blackout
blackout status
blackout user add
blackout user list
blackout user link USERNAME
blackout user lock USERNAME
blackout user unlock USERNAME
blackout user remove USERNAME
blackout cert status
blackout cert renew
blackout config current
blackout config list
blackout xray current
blackout update check
```

See [docs/commands.md](docs/commands.md) for the full command reference.

## Updating Blackout

Blackout script updates re-run the installer from the new source tree so installed files and services stay aligned with the current release.

```bash
blackout update check
```

`blackout update check` is read-only. It uses `git ls-remote` to print the installed Blackout version, the remote commit for the configured branch, and whether the install is latest or has an update available. It does not change installed files.

```bash
blackout update
```

`blackout update` clones the configured Blackout repository, backs up the current CLI/install tree, then runs the new `install.sh` in reinstall mode. It reuses saved domain, ACME email, Cloudflare token, install paths, database path, and API token when available, and only prompts for missing values.

Updates refresh services, expiry cron, the local user API service files, and the shipped `/opt/blackout/configs/default` profile. Users, certificates, database contents, custom config folders, existing API tokens, and an already installed Xray core binary are preserved.

## Updating Xray Core

Xray core updates are managed with `blackout xray`, not `blackout update`.

```bash
blackout xray update
blackout xray version v1.8.24
blackout xray current
```

`blackout xray update` installs the latest Xray-core release from official GitHub release ZIP assets. `blackout xray version VERSION` installs a specific release tag. Xray binary changes restart the Xray service.

## Certificate Management

Blackout uses `acme.sh` and installs certificates into `/etc/blackout/ssl/fullchain.pem` and `/etc/blackout/ssl/privkey.pem`.

```bash
blackout cert issue EMAIL [DOMAIN]
blackout cert renew
blackout cert change-domain DOMAIN
blackout cert status
```

`blackout cert issue EMAIL [DOMAIN]` installs `acme.sh` if needed, issues a certificate, installs the cert/key into `/etc/blackout/ssl`, stores the domain setting, and reloads Nginx when possible. Normal domains use standalone HTTP validation. Wildcard domains use Cloudflare DNS validation with the API token stored in `/etc/blackout/blackout.env`.

`blackout cert change-domain DOMAIN` updates the stored domain. For wildcard domains, it also issues and installs the wildcard certificate, re-renders the active config, and reloads services.

## Troubleshooting

Start with status and service logs:

```bash
blackout status
blackout cert status
blackout config current
systemctl status xray nginx
journalctl -u blackout-api -n 100 --no-pager
journalctl -u xray -n 100 --no-pager
journalctl -u nginx -n 100 --no-pager
nginx -t
```

Common checks:

- Confirm the domain `A` record points to this VPS before running install or certificate commands.
- Confirm ports `80` and `443` are reachable and not blocked by the VPS firewall or provider firewall.
- If standalone ACME fails, stop any other service using port `80` and run `blackout cert issue EMAIL DOMAIN` again.
- If wildcard ACME fails, confirm the Cloudflare API token can list zones and edit DNS records for the domain.
- If user links fail, confirm the user is active with `blackout user list` and that Xray is running.
- If runtime user operations fail, confirm the default profile is active and the Xray API is reachable locally.
