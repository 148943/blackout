# Blackout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Blackout Debian 12 Bash management suite for Xray-core, Nginx, acme.sh certificates, SQLite users, config profiles, self-update, and documentation.

**Architecture:** Use a small Bash CLI at `blackout` with focused libraries under `lib/`. Store runtime state in SQLite, render config profiles from `configs/`, and keep installer/service work in `install.sh` plus reusable library functions. User CRUD syncs SQLite with Xray's local API so routine user changes do not restart Xray.

**Tech Stack:** Bash, sqlite3, jq, curl, unzip, systemd, nginx, acme.sh, Xray-core GitHub release ZIPs.

---

## File Map

- Create `blackout`: CLI entrypoint, command router, interactive menu launcher.
- Create `install.sh`: fresh Debian 12 installer.
- Create `lib/common.sh`: constants, styling, root checks, command helpers, env loading, backups.
- Create `lib/db.sh`: SQLite schema, migrations, settings, user row helpers.
- Create `lib/time.sh`: duration parsing and timestamp helpers.
- Create `lib/template.sh`: token substitution for config and share templates.
- Create `lib/xray.sh`: release lookup/download/install, service management, API command wrapper, stats.
- Create `lib/users.sh`: user add/remove/modify/lock/unlock/list/online/link/expire workflows.
- Create `lib/certs.sh`: acme.sh install, issue, renew, change-domain, cert status.
- Create `lib/nginx.sh`: nginx config render, enable, test, reload.
- Create `lib/configs.sh`: profile list/current/switch/render/validate.
- Create `lib/update.sh`: `blackout update check` and `blackout update`.
- Create `lib/menu.sh`: interactive hacker-style menu.
- Create `configs/vless-ws-nginx/xray.conf`: default Xray template.
- Create `configs/vless-ws-nginx/nginx.conf`: default Nginx template.
- Create `configs/vless-ws-nginx/share.template`: VLESS sharing link template.
- Create `tests/run.sh`: local test runner.
- Create `tests/test_time.sh`: duration parsing tests.
- Create `tests/test_template.sh`: template render tests.
- Create `tests/test_xray_arch.sh`: Xray asset architecture mapping tests.
- Create `tests/test_db.sh`: schema idempotency tests.
- Create `README.md` and docs under `docs/`.

## Task 1: Shell Scaffolding, Style, And Test Harness

**Files:**
- Create: `blackout`
- Create: `lib/common.sh`
- Create: `lib/menu.sh`
- Create: `tests/run.sh`

- [ ] **Step 1: Write the failing smoke test runner**

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT_DIR/blackout"
find "$ROOT_DIR/lib" -type f -name '*.sh' -print0 | xargs -0 -r bash -n

for test_file in "$ROOT_DIR"/tests/test_*.sh; do
  [ -e "$test_file" ] || continue
  bash "$test_file"
done

echo "tests ok"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/run.sh`

Expected: FAIL because `blackout` and `lib/` do not exist.

- [ ] **Step 3: Create the CLI and common library**

Create `lib/common.sh` with:

```bash
#!/usr/bin/env bash

BLACKOUT_VERSION="${BLACKOUT_VERSION:-dev}"
BLACKOUT_LIB_DIR="${BLACKOUT_LIB_DIR:-/opt/blackout/lib}"
BLACKOUT_CONFIG_DIR="${BLACKOUT_CONFIG_DIR:-/opt/blackout/configs}"
BLACKOUT_ETC_DIR="${BLACKOUT_ETC_DIR:-/etc/blackout}"
BLACKOUT_STATE_DIR="${BLACKOUT_STATE_DIR:-/var/lib/blackout}"
BLACKOUT_DB="${BLACKOUT_DB:-$BLACKOUT_STATE_DIR/blackout.db}"
BLACKOUT_ENV="${BLACKOUT_ENV:-$BLACKOUT_ETC_DIR/blackout.env}"

if [ -f "$BLACKOUT_ENV" ]; then
  # shellcheck disable=SC1090
  . "$BLACKOUT_ENV"
fi

bo_color() {
  case "${NO_COLOR:-0}:$1" in
    1:*) printf '' ;;
    *:green) printf '\033[32m' ;;
    *:cyan) printf '\033[36m' ;;
    *:red) printf '\033[31m' ;;
    *:yellow) printf '\033[33m' ;;
    *:reset) printf '\033[0m' ;;
  esac
}

bo_log() { printf '%s[BLACKOUT]%s :: %s\n' "$(bo_color green)" "$(bo_color reset)" "$*"; }
bo_trace() { printf '%s[TRACE]%s    :: %s\n' "$(bo_color cyan)" "$(bo_color reset)" "$*"; }
bo_warn() { printf '%s[WARN]%s     :: %s\n' "$(bo_color yellow)" "$(bo_color reset)" "$*" >&2; }
bo_fail() { printf '%s[FAIL]%s     :: %s\n' "$(bo_color red)" "$(bo_color reset)" "$*" >&2; exit 1; }

bo_need_root() {
  [ "$(id -u)" -eq 0 ] || bo_fail "root required"
}

bo_need_cmd() {
  command -v "$1" >/dev/null 2>&1 || bo_fail "missing command: $1"
}

bo_backup_file() {
  local path="$1"
  [ -e "$path" ] || return 0
  local backup_dir="${BLACKOUT_BACKUP_DIR:-/var/backups/blackout}/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir"
  cp -a "$path" "$backup_dir/"
  bo_trace "backup: $path -> $backup_dir/"
}
```

Create `blackout` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SELF_DIR/lib/common.sh" ]; then
  BLACKOUT_LIB_DIR="$SELF_DIR/lib"
fi

# shellcheck disable=SC1091
. "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/common.sh"

usage() {
  cat <<'USAGE'
Blackout commands:
  blackout
  blackout user add|remove|modify|lock|unlock|list|online|link|expire
  blackout xray install|update|version|current
  blackout cert issue|renew|change-domain|status
  blackout config list|switch|current
  blackout update [check]
USAGE
}

main() {
  local area="${1:-menu}"
  case "$area" in
    menu) . "$BLACKOUT_LIB_DIR/menu.sh"; bo_menu ;;
    user) shift; . "$BLACKOUT_LIB_DIR/users.sh"; bo_user_cmd "$@" ;;
    xray) shift; . "$BLACKOUT_LIB_DIR/xray.sh"; bo_xray_cmd "$@" ;;
    cert) shift; . "$BLACKOUT_LIB_DIR/certs.sh"; bo_cert_cmd "$@" ;;
    config) shift; . "$BLACKOUT_LIB_DIR/configs.sh"; bo_config_cmd "$@" ;;
    update) shift || true; . "$BLACKOUT_LIB_DIR/update.sh"; bo_update_cmd "$@" ;;
    -h|--help|help) usage ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
```

Create `lib/menu.sh` with a minimal menu stub that routes to commands:

```bash
#!/usr/bin/env bash

bo_menu() {
  bo_log "Blackout control panel"
  printf '1) Users\n2) Xray\n3) Certificates\n4) Config\n5) Update check\n0) Exit\n'
}
```

- [ ] **Step 4: Run tests**

Run: `bash tests/run.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add blackout lib/common.sh lib/menu.sh tests/run.sh
git commit -m "feat: scaffold blackout cli"
```

## Task 2: Time, Template, And SQLite Foundation

**Files:**
- Create: `lib/time.sh`
- Create: `lib/template.sh`
- Create: `lib/db.sh`
- Create: `tests/test_time.sh`
- Create: `tests/test_template.sh`
- Create: `tests/test_db.sh`

- [ ] **Step 1: Write duration parsing tests**

Create `tests/test_time.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/lib/time.sh"

[ "$(bo_duration_seconds 12h)" = "43200" ]
[ "$(bo_duration_seconds 7d)" = "604800" ]
[ "$(bo_duration_seconds 30d)" = "2592000" ]
[ "$(bo_duration_seconds 1m)" = "2592000" ]
if bo_duration_seconds nope >/dev/null 2>&1; then
  echo "invalid duration accepted" >&2
  exit 1
fi
```

Create `tests/test_template.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/lib/template.sh"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf 'vless://{{UUID}}@{{DOMAIN}}:443?path={{WS_PATH}}#{{USERNAME}}\n' > "$tmp"
out="$(bo_render_template "$tmp" UUID abc DOMAIN example.com WS_PATH /vless USERNAME aiman)"
[ "$out" = 'vless://abc@example.com:443?path=/vless#aiman' ]
```

Create `tests/test_db.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/lib/db.sh"

tmpdb="$(mktemp)"
trap 'rm -f "$tmpdb"' EXIT
BLACKOUT_DB="$tmpdb"
bo_db_init
bo_db_init
sqlite3 "$BLACKOUT_DB" "select name from sqlite_master where type='table' and name='users';" | grep -qx users
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh`

Expected: FAIL because the libraries do not exist.

- [ ] **Step 3: Implement libraries**

Create `lib/time.sh`:

```bash
#!/usr/bin/env bash

bo_duration_seconds() {
  local value="$1" number unit
  [[ "$value" =~ ^([0-9]+)([hdm])$ ]] || return 1
  number="${BASH_REMATCH[1]}"
  unit="${BASH_REMATCH[2]}"
  case "$unit" in
    h) printf '%s\n' $((number * 3600)) ;;
    d) printf '%s\n' $((number * 86400)) ;;
    m) printf '%s\n' $((number * 2592000)) ;;
  esac
}

bo_expiry_epoch() {
  local duration="$1"
  printf '%s\n' "$(($(date +%s) + $(bo_duration_seconds "$duration")))"
}
```

Create `lib/template.sh`:

```bash
#!/usr/bin/env bash

bo_render_template() {
  local file="$1"; shift
  local content key value
  content="$(cat "$file")"
  while [ "$#" -gt 0 ]; do
    key="$1"; value="$2"; shift 2
    content="${content//\{\{$key\}\}/$value}"
  done
  printf '%s' "$content"
}
```

Create `lib/db.sh` with schema initialization and basic settings helpers:

```bash
#!/usr/bin/env bash

bo_db() {
  sqlite3 "$BLACKOUT_DB" "$@"
}

bo_db_init() {
  mkdir -p "$(dirname "$BLACKOUT_DB")"
  sqlite3 "$BLACKOUT_DB" <<'SQL'
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  uuid TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL UNIQUE,
  level INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL CHECK(status IN ('active','locked','expired')),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS traffic_snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  uplink INTEGER NOT NULL DEFAULT 0,
  downlink INTEGER NOT NULL DEFAULT 0,
  captured_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS xray_versions (
  version TEXT PRIMARY KEY,
  installed_at INTEGER NOT NULL,
  binary_path TEXT NOT NULL
);
SQL
}

bo_setting_get() {
  sqlite3 "$BLACKOUT_DB" "SELECT value FROM settings WHERE key = '$(printf "%s" "$1" | sed "s/'/''/g")';"
}

bo_setting_set() {
  local key value now
  key="$(printf "%s" "$1" | sed "s/'/''/g")"
  value="$(printf "%s" "$2" | sed "s/'/''/g")"
  now="$(date +%s)"
  sqlite3 "$BLACKOUT_DB" "INSERT INTO settings(key,value) VALUES('$key','$value') ON CONFLICT(key) DO UPDATE SET value=excluded.value;"
}
```

- [ ] **Step 4: Run tests**

Run: `bash tests/run.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/time.sh lib/template.sh lib/db.sh tests/test_time.sh tests/test_template.sh tests/test_db.sh
git commit -m "feat: add blackout state foundation"
```

## Task 3: Xray Release, Install, Service, API, And Stats Library

**Files:**
- Create: `lib/xray.sh`
- Create: `tests/test_xray_arch.sh`

- [ ] **Step 1: Write architecture mapping tests**

Create `tests/test_xray_arch.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/lib/xray.sh"

[ "$(bo_xray_asset_for_arch x86_64)" = "Xray-linux-64.zip" ]
[ "$(bo_xray_asset_for_arch amd64)" = "Xray-linux-64.zip" ]
[ "$(bo_xray_asset_for_arch aarch64)" = "Xray-linux-arm64-v8a.zip" ]
[ "$(bo_xray_asset_for_arch arm64)" = "Xray-linux-arm64-v8a.zip" ]
if bo_xray_asset_for_arch mips >/dev/null 2>&1; then
  echo "unsupported arch accepted" >&2
  exit 1
fi
```

- [ ] **Step 2: Run tests to verify failure**

Run: `bash tests/run.sh`

Expected: FAIL because `lib/xray.sh` does not exist.

- [ ] **Step 3: Implement Xray library**

Create `lib/xray.sh` with:

```bash
#!/usr/bin/env bash

bo_xray_asset_for_arch() {
  case "$1" in
    x86_64|amd64) printf 'Xray-linux-64.zip\n' ;;
    aarch64|arm64) printf 'Xray-linux-arm64-v8a.zip\n' ;;
    armv7l|armhf) printf 'Xray-linux-arm32-v7a.zip\n' ;;
    *) return 1 ;;
  esac
}

bo_xray_latest_version() {
  curl -fsSLI -o /dev/null -w '%{url_effective}\n' https://github.com/XTLS/Xray-core/releases/latest | sed 's#.*/##'
}

bo_xray_download() {
  local version="$1" dest="$2" arch asset url
  [ "$version" = latest ] && version="$(bo_xray_latest_version)"
  arch="$(uname -m)"
  asset="$(bo_xray_asset_for_arch "$arch")" || bo_fail "unsupported architecture: $arch"
  url="https://github.com/XTLS/Xray-core/releases/download/$version/$asset"
  mkdir -p "$dest"
  bo_trace "download: $url"
  curl -fL "$url" -o "$dest/$asset"
  printf '%s\n' "$dest/$asset"
}

bo_xray_install_version() {
  bo_need_root
  local version="${1:-latest}" tmp zip
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  zip="$(bo_xray_download "$version" "$tmp")"
  unzip -o "$zip" -d "$tmp/xray" >/dev/null
  install -Dm755 "$tmp/xray/xray" /usr/local/bin/xray
  [ -f "$tmp/xray/geoip.dat" ] && install -Dm644 "$tmp/xray/geoip.dat" /usr/local/share/xray/geoip.dat
  [ -f "$tmp/xray/geosite.dat" ] && install -Dm644 "$tmp/xray/geosite.dat" /usr/local/share/xray/geosite.dat
  systemctl restart xray
}

bo_xray_api() {
  local service="$1"; shift
  xray api "$service" --server=127.0.0.1:60001 "$@"
}

bo_xray_cmd() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    install) bo_xray_install_version "${1:-latest}" ;;
    update) bo_xray_install_version latest ;;
    version) bo_xray_install_version "${1:?version required}" ;;
    current) xray version ;;
    *) bo_fail "unknown xray command: ${cmd:-}" ;;
  esac
}
```

- [ ] **Step 4: Run tests**

Run: `bash tests/run.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/xray.sh tests/test_xray_arch.sh
git commit -m "feat: add xray core management"
```

## Task 4: Config Profiles, Nginx, And Certificates

**Files:**
- Create: `lib/configs.sh`
- Create: `lib/nginx.sh`
- Create: `lib/certs.sh`
- Create: `configs/vless-ws-nginx/xray.conf`
- Create: `configs/vless-ws-nginx/nginx.conf`
- Create: `configs/vless-ws-nginx/share.template`

- [ ] **Step 1: Add default profile templates**

Create `configs/vless-ws-nginx/xray.conf` as JSON template with `{{WS_PATH}}`, `{{XRAY_API_PORT}}`, and an empty `clients` list. It must include API, HandlerService, StatsService, policy user stats, a dokodemo API inbound, a VLESS websocket inbound using `/dev/shm/blackout-vless.sock`, and a freedom outbound.

Create `configs/vless-ws-nginx/nginx.conf` using `{{DOMAIN}}`, `/etc/blackout/ssl/fullchain.pem`, `/etc/blackout/ssl/privkey.pem`, and a websocket `location = {{WS_PATH}}` proxying to `http://unix:/dev/shm/blackout-vless.sock`.

Create `configs/vless-ws-nginx/share.template`:

```text
vless://{{UUID}}@{{DOMAIN}}:443?type=ws&security=tls&path={{WS_PATH}}&host={{DOMAIN}}#{{USERNAME}}
```

- [ ] **Step 2: Implement profile and nginx helpers**

Create `lib/configs.sh` with command routing for `list`, `current`, and `switch`. `switch` must render templates through `bo_render_template`, write staged files, validate JSON with `jq`, run `nginx -t` after staging nginx config, then restart Xray and reload Nginx.

Create `lib/nginx.sh` with `bo_nginx_install_site`, `bo_nginx_test`, and `bo_nginx_reload`.

- [ ] **Step 3: Implement certificate helpers**

Create `lib/certs.sh` with:

```bash
bo_acme_bin() { printf '%s/.acme.sh/acme.sh\n' "${HOME:-/root}"; }
bo_acme_install() { [ -x "$(bo_acme_bin)" ] || curl https://get.acme.sh | sh -s email="${1:?email required}"; }
bo_cert_issue() { systemctl stop nginx || true; "$(bo_acme_bin)" --issue --standalone -d "$1"; "$(bo_acme_bin)" --install-cert -d "$1" --fullchain-file /etc/blackout/ssl/fullchain.pem --key-file /etc/blackout/ssl/privkey.pem; systemctl start nginx; }
bo_cert_renew() { systemctl stop nginx || true; "$(bo_acme_bin)" --renew -d "$(bo_setting_get domain)" --force; systemctl start nginx; }
```

Wire `bo_cert_cmd issue|renew|change-domain|status` to these functions and update the `settings` table for domain changes.

- [ ] **Step 4: Verify syntax**

Run: `bash tests/run.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/configs.sh lib/nginx.sh lib/certs.sh configs/vless-ws-nginx
git commit -m "feat: add profiles nginx and certificates"
```

## Task 5: User Management With SQLite And Xray API

**Files:**
- Create: `lib/users.sh`
- Modify: `lib/db.sh`
- Modify: `blackout`

- [ ] **Step 1: Add DB user helper tests**

Extend `tests/test_db.sh` with inserting, listing, locking, and expiry status checks using helper functions:

```bash
bo_db_user_insert aiman 00000000-0000-0000-0000-000000000001 aiman@example 0 active 100 200
bo_db_user_status aiman | grep -qx active
bo_db_user_set_status aiman locked
bo_db_user_status aiman | grep -qx locked
```

- [ ] **Step 2: Run tests to verify failure**

Run: `bash tests/run.sh`

Expected: FAIL because DB user helpers do not exist.

- [ ] **Step 3: Implement DB helpers**

Add to `lib/db.sh`:

```bash
bo_sql_quote() { printf "%s" "$1" | sed "s/'/''/g"; }
bo_db_user_insert() {
  sqlite3 "$BLACKOUT_DB" "INSERT INTO users(username,uuid,email,level,status,created_at,expires_at,updated_at) VALUES('$(bo_sql_quote "$1")','$(bo_sql_quote "$2")','$(bo_sql_quote "$3")',$4,'$(bo_sql_quote "$5")',$6,$7,$(date +%s));"
}
bo_db_user_status() {
  sqlite3 "$BLACKOUT_DB" "SELECT status FROM users WHERE username='$(bo_sql_quote "$1")';"
}
bo_db_user_set_status() {
  sqlite3 "$BLACKOUT_DB" "UPDATE users SET status='$(bo_sql_quote "$2")', updated_at=$(date +%s) WHERE username='$(bo_sql_quote "$1")';"
}
```

- [ ] **Step 4: Implement user workflows**

Create `lib/users.sh` with `bo_user_cmd`. The direct command paths must support:

```bash
bo_user_cmd add
bo_user_cmd remove USERNAME
bo_user_cmd modify USERNAME
bo_user_cmd lock USERNAME
bo_user_cmd unlock USERNAME
bo_user_cmd list
bo_user_cmd online
bo_user_cmd link USERNAME
bo_user_cmd expire
```

`add` prompts for username and duration, generates `uuidgen`, inserts SQLite row, and calls Xray API AddUser. `lock` and `remove` call Xray RemoveUser before final DB status/delete. `link` renders the active profile `share.template`.

- [ ] **Step 5: Run tests**

Run: `bash tests/run.sh`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/users.sh lib/db.sh blackout tests/test_db.sh
git commit -m "feat: add sqlite backed user management"
```

## Task 6: Installer And Self-Update

**Files:**
- Create: `install.sh`
- Create: `lib/update.sh`

- [ ] **Step 1: Implement self-update commands**

Create `lib/update.sh`:

```bash
#!/usr/bin/env bash

bo_update_check() {
  local repo="${BLACKOUT_REPO:-git@github.com:148943/blackout.git}" branch="${BLACKOUT_BRANCH:-master}"
  local remote
  remote="$(git ls-remote "$repo" "refs/heads/$branch" | awk '{print $1}')"
  bo_log "installed: ${BLACKOUT_VERSION:-dev}"
  bo_log "remote $branch: ${remote:-unknown}"
}

bo_update_run() {
  bo_need_root
  local repo="${BLACKOUT_REPO:-git@github.com:148943/blackout.git}" branch="${BLACKOUT_BRANCH:-master}"
  local tmp backup
  tmp="$(mktemp -d)"
  backup="/var/backups/blackout/update-$(date +%Y%m%d-%H%M%S)"
  git clone --depth 1 --branch "$branch" "$repo" "$tmp/src"
  mkdir -p "$backup"
  [ -e /usr/local/bin/blackout ] && cp -a /usr/local/bin/blackout "$backup/"
  [ -d /opt/blackout ] && cp -a /opt/blackout "$backup/opt-blackout"
  install -Dm755 "$tmp/src/blackout" /usr/local/bin/blackout
  mkdir -p /opt/blackout
  cp -a "$tmp/src/lib" "$tmp/src/configs" /opt/blackout/
  bo_log "updated Blackout from $repo@$branch"
}

bo_update_cmd() {
  case "${1:-run}" in
    check) bo_update_check ;;
    run|"") bo_update_run ;;
    *) bo_fail "unknown update command: $1" ;;
  esac
}
```

- [ ] **Step 2: Implement installer**

Create `install.sh` that:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLACKOUT_LIB_DIR="$ROOT_DIR/lib"
. "$ROOT_DIR/lib/common.sh"
. "$ROOT_DIR/lib/db.sh"
. "$ROOT_DIR/lib/xray.sh"
. "$ROOT_DIR/lib/certs.sh"
. "$ROOT_DIR/lib/configs.sh"

bo_need_root
. /etc/os-release
[ "${VERSION_ID:-}" = "12" ] || bo_fail "Debian 12 required"

apt-get update
apt-get install -y curl unzip jq sqlite3 nginx socat cron ca-certificates git uuid-runtime

install -Dm755 "$ROOT_DIR/blackout" /usr/local/bin/blackout
mkdir -p /opt/blackout /etc/blackout/ssl /var/lib/blackout
cp -a "$ROOT_DIR/lib" "$ROOT_DIR/configs" /opt/blackout/

read -r -p "Domain: " domain
read -r -p "ACME email: " email

cat >/etc/blackout/blackout.env <<EOF_ENV
BLACKOUT_REPO="git@github.com:148943/blackout.git"
BLACKOUT_BRANCH="master"
BLACKOUT_VERSION="dev"
BLACKOUT_INSTALL_DIR="/opt/blackout"
BLACKOUT_LIB_DIR="/opt/blackout/lib"
BLACKOUT_CONFIG_DIR="/opt/blackout/configs"
BLACKOUT_DB="/var/lib/blackout/blackout.db"
EOF_ENV

BLACKOUT_DB=/var/lib/blackout/blackout.db
bo_db_init
bo_setting_set domain "$domain"
bo_setting_set ws_path "/vless"
bo_acme_install "$email"
bo_cert_issue "$domain"
bo_xray_install_version latest
bo_config_switch vless-ws-nginx
systemctl enable --now xray nginx
bo_log "install complete"
```

- [ ] **Step 3: Run syntax tests**

Run: `bash tests/run.sh`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add install.sh lib/update.sh
git commit -m "feat: add installer and self update"
```

## Task 7: Documentation

**Files:**
- Create: `README.md`
- Create: `docs/commands.md`
- Create: `docs/config-profiles.md`
- Create: `docs/user-management.md`
- Create: `docs/certificates.md`
- Create: `docs/troubleshooting.md`

- [ ] **Step 1: Write README fresh VPS guide**

Include these exact sections:

```text
Blackout
Requirements
Fresh Debian 12 VPS Install
First User
Common Commands
Updating Blackout
Updating Xray Core
Certificate Management
Troubleshooting
```

The install guide must show:

```bash
apt update && apt upgrade -y
apt install -y git curl
git clone git@github.com:148943/blackout.git
cd blackout
bash install.sh
blackout user add
blackout user link USERNAME
```

- [ ] **Step 2: Write command and feature docs**

Document every public command from the spec. Explain that `blackout update check` is read-only and `blackout update` updates Blackout scripts only, not Xray core.

- [ ] **Step 3: Run markdown and shell verification**

Run: `bash tests/run.sh`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/commands.md docs/config-profiles.md docs/user-management.md docs/certificates.md docs/troubleshooting.md
git commit -m "docs: add blackout user documentation"
```

## Task 8: Final Verification

**Files:**
- Modify only files required by failures found during verification.

- [ ] **Step 1: Run syntax tests**

Run: `bash tests/run.sh`

Expected: PASS with `tests ok`.

- [ ] **Step 2: Run shellcheck if available**

Run:

```bash
if command -v shellcheck >/dev/null 2>&1; then shellcheck blackout install.sh lib/*.sh tests/*.sh; fi
```

Expected: PASS or no output when shellcheck is unavailable.

- [ ] **Step 3: Validate default Xray JSON template after rendering**

Run a render command with sample values and pipe to `jq .`.

Expected: valid JSON.

- [ ] **Step 4: Inspect Git state**

Run: `git status --short`

Expected: only intentional untracked reference files remain, or a clean tree after adding intended project files.

- [ ] **Step 5: Commit final fixes**

```bash
git add blackout install.sh lib configs tests README.md docs
git commit -m "chore: verify blackout implementation"
```

Skip this commit if no final fixes were needed.

## Self-Review Notes

- Spec coverage: installer, Xray management, SQLite users, Xray API path, Nginx reverse proxy, acme.sh standalone certificates, config profiles, self-update, tests, and docs are covered.
- Scope: this is a large first version, but tasks are split by subsystem and each produces testable code.
- Self-update scope: only `blackout update check` and `blackout update` are included.
