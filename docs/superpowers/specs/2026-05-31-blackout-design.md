# Blackout Design

## Goal

Blackout is a Debian 12 Bash management suite for Xray-core, Nginx reverse proxying, ACME certificates, configuration profiles, and SQLite-backed user management. It installs from a fresh VPS, manages VLESS users through the Xray API without routine Xray restarts, and provides a compact hacker-style terminal UI plus direct commands.

## Target Platform

- Debian 12.
- Root shell during installation and service management.
- Nginx as the public reverse proxy.
- acme.sh for TLS certificates.
- Xray-core downloaded directly from official GitHub release ZIP assets.
- SQLite as the local state database.

## Repository Layout

```text
install.sh
blackout
lib/
  common.sh
  db.sh
  xray.sh
  users.sh
  certs.sh
  configs.sh
  nginx.sh
  menu.sh
configs/
  vless-ws-nginx/
    xray.conf
    nginx.conf
    share.template
docs/
README.md
docs/commands.md
docs/config-profiles.md
docs/user-management.md
docs/certificates.md
docs/troubleshooting.md
```

## Installed Layout

```text
/usr/local/bin/blackout
/opt/blackout/lib/*.sh
/opt/blackout/configs/*/
/var/lib/blackout/blackout.db
/etc/blackout/blackout.env
/etc/blackout/ssl/fullchain.pem
/etc/blackout/ssl/privkey.pem
/etc/xray/config.json
/etc/systemd/system/xray.service
/etc/nginx/sites-available/blackout.conf
/etc/nginx/sites-enabled/blackout.conf
```

## CLI Shape

Blackout supports both an interactive menu and direct commands.

```bash
blackout
blackout user add
blackout user remove USERNAME
blackout user modify USERNAME
blackout user lock USERNAME
blackout user unlock USERNAME
blackout user list
blackout user online
blackout user link USERNAME
blackout user expire
blackout xray install latest
blackout xray update
blackout xray version VERSION
blackout xray current
blackout cert issue DOMAIN
blackout cert renew
blackout cert change-domain DOMAIN
blackout cert status
blackout config list
blackout config switch PROFILE
blackout config current
blackout update check
blackout update
```

The output style uses ANSI color and compact prefixes:

```text
[BLACKOUT] :: root access confirmed
[TRACE]    :: xray api reachable
[FAIL]     :: domain does not resolve to this server
```

Direct commands must be scriptable and return non-zero on failure.

## Installer

`install.sh` targets a fresh Debian 12 VPS. It must:

1. Require root.
2. Check Debian 12 and fail clearly on other systems unless a future force flag is added.
3. Install packages: `curl`, `unzip`, `jq`, `sqlite3`, `nginx`, `socat`, `cron`, and `ca-certificates`.
4. Install acme.sh if it is missing.
5. Download Xray-core from official GitHub releases, using direct release ZIP assets.
6. Install Xray binary and geo assets.
7. Create the Xray systemd service.
8. Install Blackout CLI, libraries, and config profiles.
9. Ask for domain and ACME email.
10. Issue the certificate with acme.sh standalone mode.
11. Install cert/key into `/etc/blackout/ssl`.
12. Render the default `vless-ws-nginx` Xray config.
13. Render the matching Nginx reverse proxy config.
14. Enable and start Xray and Nginx.
15. Initialize SQLite.
16. Install expiry and certificate renewal automation through cron or systemd timers.

Because standalone ACME is the selected challenge method, Blackout stops Nginx before initial issue, domain changes, and forced renewals, then starts or reloads Nginx afterward.

## Xray Core Management

Blackout downloads Xray directly from GitHub release assets. Architecture detection maps Debian architecture to the correct asset name, such as `Xray-linux-64.zip` for x86_64. If checksum assets are available in the release, Blackout verifies the ZIP before replacing the installed binary.

Supported commands:

```bash
blackout xray install latest
blackout xray install VERSION
blackout xray update
blackout xray version VERSION
blackout xray current
```

Changing the Xray core binary is allowed to restart the Xray service. Routine user management must use the Xray API instead of restarting Xray.

## Xray API Use

The default Xray config exposes a local API inbound on `127.0.0.1`. It enables handler and stats services so Blackout can:

- Add users at runtime.
- Remove users at runtime.
- Read per-user traffic counters.
- Monitor activity by comparing stats deltas over a short interval.

The active inbound tag defaults to `vless`.

## SQLite Data Model

SQLite lives at `/var/lib/blackout/blackout.db`.

```text
users
- id
- username
- uuid
- email
- level
- status: active | locked | expired
- created_at
- expires_at
- updated_at

traffic_snapshots
- id
- username
- uplink
- downlink
- captured_at

settings
- key
- value

xray_versions
- version
- installed_at
- binary_path
```

VLESS authentication uses the generated UUID.

## User Management

Creating a user asks for:

```text
username
duration
```

Duration accepts compact values such as `12h`, `7d`, `30d`, and `1m`. Blackout computes `expires_at`, generates a UUID, stores the user in SQLite, and calls Xray API `AddUser` for the active inbound.

User operations:

```text
add       create DB row and call Xray AddUser
remove    call Xray RemoveUser and remove or archive the DB row
modify    update duration or status and sync Xray state
lock      call Xray RemoveUser and set status to locked
unlock    call Xray AddUser and set status to active when not expired
list      show username, status, expiry, and link availability
online    compare Xray stats deltas and mark users with recent traffic as active
expire    lock users whose expires_at has passed
link      render share.template using domain, path, UUID, and username
```

Online monitoring is traffic-based. Blackout marks a user as active when their Xray uplink or downlink counter changes during the sample window.

## Certificates

Blackout manages TLS with acme.sh.

Supported commands:

```bash
blackout cert issue DOMAIN
blackout cert renew
blackout cert change-domain DOMAIN
blackout cert status
```

The default challenge method is standalone HTTP challenge on port 80. Blackout coordinates Nginx around ACME operations:

1. Stop Nginx.
2. Run acme.sh standalone issue or renew.
3. Install the cert and key into `/etc/blackout/ssl`.
4. Start or reload Nginx.

`change-domain` updates Blackout settings, issues a certificate for the new domain, rerenders Xray/Nginx configs, validates them, then reloads services.

## Config Profiles

Every config profile is a folder with:

```text
xray.conf
nginx.conf
share.template
```

The first shipped profile is `vless-ws-nginx`. It is adapted from `_reference/vless-sample.json` and `_reference/nginx-sample.conf`, with Blackout paths, Xray API support, stats support, acme-managed TLS, and Nginx reverse proxying.

`blackout config switch PROFILE` renders the selected profile with current settings, validates JSON with `jq`, validates Xray config with `xray test` when available, validates Nginx with `nginx -t`, then restarts or reloads services.

## Blackout Self-Update

Blackout script updates are separate from Xray core updates.

Supported commands:

```bash
blackout update check
blackout update
```

`blackout update check` fetches remote metadata and prints the installed version and latest available version or commit. It must not change installed files.

`blackout update` fetches the latest Blackout source from the configured repository, backs up current CLI, library, and template files internally, updates `/usr/local/bin/blackout` and `/opt/blackout`, runs database migrations if present, and keeps users, certificates, domain settings, and installed Xray version unchanged.

`install.sh` writes update metadata into `/etc/blackout/blackout.env`:

```bash
BLACKOUT_REPO="https://github.com/148943/blackout.git"
BLACKOUT_BRANCH="master"
BLACKOUT_VERSION="dev"
BLACKOUT_INSTALL_DIR="/opt/blackout"
```

## Error Handling

Blackout must:

- Fail fast when not run as root for commands that need root.
- Validate Debian 12 during install.
- Warn if a domain does not resolve to the server before ACME issue.
- Validate generated Xray and Nginx configs before replacing active configs.
- Back up configs and binaries before replacement.
- Keep SQLite and Xray API state synchronized as much as possible.
- Print the failing command or the next useful log command when service operations fail.

SQLite writes should happen in a predictable order. For user creation, the DB row is created first with enough information to retry Xray sync, then the Xray API call activates the user. For lock/remove, Xray removal is attempted before the DB status is finalized so the service does not leave unwanted active users.

## Testing

The Bash project uses pragmatic shell testing:

```text
bash -n for syntax
shellcheck when available
unit-style tests for duration parsing
unit-style tests for template rendering
unit-style tests for architecture asset mapping
idempotency tests for DB schema initialization
jq validation for generated Xray JSON
nginx -t validation on systems with nginx installed
xray test validation on systems with xray installed
```

Tests should avoid requiring a real domain or live ACME issue in normal development.

## Documentation

`README.md` must include a fresh Debian 12 VPS guide:

```text
1. Point the domain A record to the VPS.
2. SSH as root.
3. Run apt update and apt upgrade.
4. Install git and curl if missing.
5. Clone the Blackout repo.
6. Run install.sh.
7. Create the first user.
8. Copy the generated VLESS link.
9. Use common commands for users, certs, configs, Xray updates, and Blackout updates.
```

Additional docs:

```text
docs/commands.md
docs/config-profiles.md
docs/user-management.md
docs/certificates.md
docs/troubleshooting.md
```
