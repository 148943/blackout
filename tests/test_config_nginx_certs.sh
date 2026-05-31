#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bin="$tmp/bin"
mkdir -p "$bin" "$tmp/etc" "$tmp/state" "$tmp/configs" "$tmp/home/.acme.sh"
cp -a "$ROOT_DIR/configs"/* "$tmp/configs/" 2>/dev/null || true

cat >"$bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$BLACKOUT_TEST_LOG"
SH
chmod +x "$bin/systemctl"

cat >"$bin/nginx" <<'SH'
#!/usr/bin/env bash
printf 'nginx %s\n' "$*" >>"$BLACKOUT_TEST_LOG"
SH
chmod +x "$bin/nginx"

cat >"$bin/jq" <<'SH'
#!/usr/bin/env bash
printf 'jq %s\n' "$*" >>"$BLACKOUT_TEST_LOG"
if [ "$#" -ne 3 ] || [ "$1" != "-e" ] || [ "$2" != "." ]; then
  printf 'unexpected jq command shape\n' >&2
  exit 2
fi
python3 -m json.tool "$3" >/dev/null
SH
chmod +x "$bin/jq"

cat >"$tmp/home/.acme.sh/acme.sh" <<'SH'
#!/usr/bin/env bash
printf 'acme.sh %s\n' "$*" >>"$BLACKOUT_TEST_LOG"
SH
chmod +x "$tmp/home/.acme.sh/acme.sh"

export PATH="$bin:$PATH"
export HOME="$tmp/home"
export BLACKOUT_TEST_LOG="$tmp/calls.log"
export BLACKOUT_LIB_DIR="$ROOT_DIR/lib"
export BLACKOUT_CONFIG_DIR="$tmp/configs"
export BLACKOUT_ETC_DIR="$tmp/etc"
export BLACKOUT_STATE_DIR="$tmp/state"
export BLACKOUT_DB="$tmp/state/blackout.db"
export BLACKOUT_XRAY_CONFIG="$tmp/etc/xray/config.json"
export BLACKOUT_NGINX_AVAILABLE_DIR="$tmp/etc/nginx/sites-available"
export BLACKOUT_NGINX_ENABLED_DIR="$tmp/etc/nginx/sites-enabled"

. "$ROOT_DIR/lib/common.sh"
. "$ROOT_DIR/lib/db.sh"
. "$ROOT_DIR/lib/configs.sh"
. "$ROOT_DIR/lib/certs.sh"

bo_db_init
bo_setting_set domain example.com
bo_setting_set ws_path /blackout
bo_setting_set xray_api_port 60001

[ "$(bo_config_current)" = "vless-ws-nginx" ]
bo_config_list | grep -qx 'vless-ws-nginx'

bo_config_switch vless-ws-nginx

[ -s "$BLACKOUT_XRAY_CONFIG" ]
[ -s "$tmp/etc/nginx/sites-available/blackout" ]
[ -L "$tmp/etc/nginx/sites-enabled/blackout" ]
[ "$(bo_setting_get profile)" = "vless-ws-nginx" ]

jq -e . "$BLACKOUT_XRAY_CONFIG" >/dev/null
grep -q 'location = /blackout' "$tmp/etc/nginx/sites-available/blackout"
grep -q 'proxy_pass http://unix:/dev/shm/blackout-vless.sock' "$tmp/etc/nginx/sites-available/blackout"
grep -q 'systemctl restart xray' "$BLACKOUT_TEST_LOG"
grep -q 'systemctl reload nginx' "$BLACKOUT_TEST_LOG"

bo_cert_cmd change-domain new.example.com
[ "$(bo_setting_get domain)" = "new.example.com" ]

bo_cert_cmd issue admin@example.com
grep -q 'acme.sh --issue --standalone -d new.example.com' "$BLACKOUT_TEST_LOG"
grep -q "acme.sh --install-cert -d new.example.com --fullchain-file $tmp/etc/ssl/fullchain.pem --key-file $tmp/etc/ssl/privkey.pem" "$BLACKOUT_TEST_LOG"

bo_cert_cmd renew
grep -q 'acme.sh --renew -d new.example.com --force' "$BLACKOUT_TEST_LOG"
