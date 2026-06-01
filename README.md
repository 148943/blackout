# Blackout

Blackout is a Bash management suite for Debian 12 VPS hosts running Xray-core behind an Nginx reverse proxy. It installs and manages the default `vless-ws-nginx` profile, TLS certificates from `acme.sh`, SQLite-backed users, Xray API runtime user changes, Xray core updates, and Blackout script updates.

Routine user operations use the local Xray API instead of restarting Xray. State is stored in SQLite at `/var/lib/blackout/blackout.db` after installation.

More documentation:

- [Command reference](docs/commands.md)
- [Config profiles](docs/config-profiles.md)
- [User management](docs/user-management.md)
- [Certificates](docs/certificates.md)
- [Troubleshooting](docs/troubleshooting.md)

## Requirements

- Fresh Debian 12 VPS.
- Root shell or `sudo -i`.
- A domain name with an `A` record pointing to the VPS IPv4 address. Add an `AAAA` record only if IPv6 is configured and reachable.
- Ports `80` and `443` open from the internet.
- `git` access to `git@github.com:148943/blackout.git`. If using the SSH URL, the VPS needs a GitHub deploy key or SSH key with repository access.

Blackout installs its runtime dependencies during `bash install.sh`: `curl`, `unzip`, `jq`, `sqlite3`, `nginx`, `socat`, `cron`, `ca-certificates`, `git`, and `uuid-runtime`.

## Fresh Debian 12 VPS Install

Run these commands as root on the VPS:

```bash
apt update && apt upgrade -y
apt install -y git curl
git clone git@github.com:148943/blackout.git
cd blackout
bash install.sh
blackout user add
blackout user link USERNAME
```

`bash install.sh` prompts for:

- `Domain`: the domain whose DNS `A` record already points to the VPS.
- `ACME email`: the email address used by `acme.sh`.

The installer checks Debian 12, installs packages, initializes SQLite, installs Blackout under `/opt/blackout`, installs the CLI at `/usr/local/bin/blackout`, installs Xray-core, issues a certificate with `acme.sh` standalone mode, renders the `vless-ws-nginx` Xray and Nginx configs, and enables Xray and Nginx.

Because standalone ACME needs port `80`, the certificate flow stops Nginx while issuing or renewing and starts it afterward.

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

`blackout update check` is read-only. It uses `git ls-remote` to print the installed Blackout version and the remote commit for the configured branch. It does not change installed files.

```bash
blackout update
```

`blackout update` updates the Blackout scripts and config templates only. It clones the configured Blackout repository, backs up the current CLI/install tree, replaces `/usr/local/bin/blackout`, `lib/`, and `configs/`, and leaves users, certificates, domain settings, and the installed Xray core untouched.

## Updating Xray Core

Xray core updates are managed with `blackout xray`, not `blackout update`.

```bash
blackout xray update
blackout xray version v1.8.24
blackout xray current
```

`blackout xray update` installs the latest Xray-core release from official GitHub release ZIP assets. `blackout xray version VERSION` installs a specific release tag. Xray binary changes restart the Xray service.

## Certificate Management

Blackout uses `acme.sh` in standalone mode and installs certificates into `/etc/blackout/ssl/fullchain.pem` and `/etc/blackout/ssl/privkey.pem`.

```bash
blackout cert issue EMAIL [DOMAIN]
blackout cert renew
blackout cert change-domain DOMAIN
blackout cert status
```

`blackout cert issue EMAIL [DOMAIN]` installs `acme.sh` if needed, issues a certificate, installs the cert/key into `/etc/blackout/ssl`, stores the domain setting, and reloads Nginx when possible.

`blackout cert change-domain DOMAIN` currently updates the stored domain setting only. Run `blackout cert issue EMAIL DOMAIN` after changing domains to issue and install a certificate for the new name.

## Troubleshooting

Start with status and service logs:

```bash
blackout cert status
blackout config current
systemctl status xray nginx
journalctl -u xray -n 100 --no-pager
journalctl -u nginx -n 100 --no-pager
nginx -t
```

Common checks:

- Confirm the domain `A` record points to this VPS before running install or certificate commands.
- Confirm ports `80` and `443` are reachable and not blocked by the VPS firewall or provider firewall.
- If ACME fails, stop any other service using port `80` and run `blackout cert issue EMAIL DOMAIN` again.
- If user links fail, confirm the user is active with `blackout user list` and that Xray is running.
- If runtime user operations fail, confirm the default profile is active and the Xray API is reachable locally.
