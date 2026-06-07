# Blackout

Blackout is a Bash management suite for Debian 12 VPS hosts running Xray-core behind an Nginx reverse proxy. It installs and manages the `default` profile, TLS certificates from `acme.sh`, SQLite-backed users, automated expiry cleanup, Xray API runtime user changes, Xray core updates, and Blackout script updates.

Routine user operations use the local Xray API instead of restarting Xray. State is stored in SQLite at `/var/lib/blackout/blackout.db` after installation.

Fresh installs add `/etc/cron.d/blackout-expire`, which runs `blackout user expire` every 5 minutes.

More documentation:

- [Command reference](docs/commands.md)
- [Config profiles](docs/config-profiles.md)
- [User management](docs/user-management.md)
- [User API](docs/api.md)
- [Certificates](docs/certificates.md)
- [Troubleshooting](docs/troubleshooting.md)

## Requirements

- Fresh Debian 12 VPS.
- Root shell or `sudo -i`.
- A domain name with an `A` record pointing to the VPS IPv4 address. Add an `AAAA` record only if IPv6 is configured and reachable.
- Ports `80` and `443` open from the internet.
- `git` access to `https://github.com/148943/blackout.git`.
- For wildcard domains such as `*.new.example.com`, a Cloudflare API token with zone read and DNS edit permissions.

Blackout installs its runtime dependencies during `bash install.sh`: `curl`, `unzip`, `jq`, `sqlite3`, `nginx`, `socat`, `cron`, `ca-certificates`, `git`, `uuid-runtime`, and `python3`.

## Fresh Debian 12 VPS Install

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

The installer checks Debian 12, installs packages, initializes SQLite, installs Blackout under `/opt/blackout`, installs the CLI at `/usr/local/bin/blackout`, installs Xray-core, issues a certificate, renders the `default` Xray and Nginx configs, and enables Xray, Nginx, and the local `blackout-api` service.

Normal domains use `acme.sh` standalone validation on port `80`. Wildcard domains use Cloudflare DNS validation and automatically request both the base domain and wildcard name, for example `new.example.com` and `*.new.example.com`.

## First User

Create the first user:

```bash
blackout user add
```

The prompt asks for username and duration such as `12h`, `7d`, or `1m`. Blackout stores the user in SQLite, generates a UUID, and adds the VLESS client to the running Xray instance through the local Xray API.

Print the client link:

```bash
blackout user link USERNAME
```

The default link uses TLS on port `443`, WebSocket transport, the configured domain, and the configured WebSocket path.

## Common Commands

```bash
blackout
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

Blackout script updates are separate from Xray core updates.

```bash
blackout update check
```

`blackout update check` is read-only. It uses `git ls-remote` to print the installed Blackout version, the remote commit for the configured branch, and whether the install is latest or has an update available. It does not change installed files.

```bash
blackout update
```

`blackout update` updates the Blackout scripts and the shipped default config only. It clones the configured Blackout repository, backs up the current CLI/install tree, replaces `/usr/local/bin/blackout`, `lib/`, and `/opt/blackout/configs/default`, records the installed Blackout commit in `/etc/blackout/blackout.env`, and leaves users, certificates, domain settings, custom config folders, and the installed Xray core untouched.

Updates also refresh the local user API service files. Existing API tokens are preserved; older installs without a token get one during update.

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
