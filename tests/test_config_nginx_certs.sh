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
active="$BLACKOUT_NGINX_AVAILABLE_DIR/blackout"
if [ "${BLACKOUT_NGINX_FAIL_ON_BAD_CONFIG:-0}" = "1" ] && [ -e "$active" ] && grep -q 'FAIL_NGINX' "$active"; then
  exit 1
fi
SH
chmod +x "$bin/nginx"

cat >"$bin/xray" <<'SH'
#!/usr/bin/env bash
printf 'xray %s\n' "$*" >>"$BLACKOUT_TEST_LOG"
case " $* " in
  *" api adu "*)
    config="${@: -1}"
    python3 - "$config" >>"$BLACKOUT_TEST_LOG" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as config_file:
    config = json.load(config_file)

client = config["inbounds"][0]["settings"]["clients"][0]
print(f"replayed {client['email']} {client['id']} {client['level']}")
PY
    ;;
esac
SH
chmod +x "$bin/xray"

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
case " $* " in
  *" --issue "*)
    [ "${BLACKOUT_ACME_FAIL_ISSUE:-0}" = "1" ] && exit 42
    [ "${BLACKOUT_ACME_SKIP_ISSUE:-0}" = "1" ] && exit 2
    ;;
  *" --renew "*)
    [ "${BLACKOUT_ACME_FAIL_RENEW:-0}" = "1" ] && exit 43
    ;;
  *" --install-cert "*)
    [ "${BLACKOUT_ACME_FAIL_INSTALL:-0}" = "1" ] && exit 44
    ;;
esac
exit 0
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
. "$ROOT_DIR/lib/users.sh"

bo_db_init
bo_setting_set domain example.com
bo_setting_set ws_path /blackout
bo_setting_set xray_api_port 60001
bo_db_user_insert replayed 00000000-0000-0000-0000-000000000021 replayed@example 2 active 100 4102444800
bo_db_user_insert locked 00000000-0000-0000-0000-000000000022 locked@example 0 locked 100 4102444800
bo_db_user_insert expired 00000000-0000-0000-0000-000000000023 expired@example 0 active 100 101

[ "$(bo_config_current)" = "vless-ws-nginx" ]
bo_config_list | grep -qx 'vless-ws-nginx'

bo_config_switch vless-ws-nginx

[ -s "$BLACKOUT_XRAY_CONFIG" ]
[ -s "$tmp/etc/nginx/sites-available/blackout" ]
[ -L "$tmp/etc/nginx/sites-enabled/blackout" ]
[ "$(bo_setting_get profile)" = "vless-ws-nginx" ]

jq -e . "$BLACKOUT_XRAY_CONFIG" >/dev/null
rendered_inbound="$(
  python3 - "$BLACKOUT_XRAY_CONFIG" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as config_file:
    config = json.load(config_file)

for inbound in config["inbounds"]:
    if inbound["tag"] != "api":
        print(inbound["tag"])
        break
PY
)"
[ "$rendered_inbound" = "$(bo_user_active_inbound)" ]
grep -q 'blackout-vless.sock,0666' "$BLACKOUT_XRAY_CONFIG"
grep -q 'location = /blackout' "$tmp/etc/nginx/sites-available/blackout"
grep -q 'proxy_pass http://unix:/dev/shm/blackout-vless.sock:/blackout' "$tmp/etc/nginx/sites-available/blackout"
grep -q 'systemctl restart xray' "$BLACKOUT_TEST_LOG"
grep -q 'replayed replayed 00000000-0000-0000-0000-000000000021 2' "$BLACKOUT_TEST_LOG"
if grep -q 'replayed locked ' "$BLACKOUT_TEST_LOG" || grep -q 'replayed expired ' "$BLACKOUT_TEST_LOG"; then
  echo "inactive user replayed after config restart" >&2
  exit 1
fi
grep -q 'systemctl reload nginx' "$BLACKOUT_TEST_LOG"

sqlite3 "$BLACKOUT_DB" "DELETE FROM settings WHERE key = 'xray_api_port';"
export BLACKOUT_XRAY_API_PORT=61001
bo_config_switch vless-ws-nginx
rendered_api_port="$(
  python3 - "$BLACKOUT_XRAY_CONFIG" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as config_file:
    config = json.load(config_file)

for inbound in config["inbounds"]:
    if inbound["tag"] == "api":
        print(inbound["port"])
        break
PY
)"
[ "$rendered_api_port" = "61001" ]
[ "$(bo_setting_get xray_api_port)" = "61001" ]
unset BLACKOUT_XRAY_API_PORT

before_nginx="$(cat "$tmp/etc/nginx/sites-available/blackout")"
mkdir -p "$tmp/configs/bad-nginx"
cp "$tmp/configs/vless-ws-nginx/xray.conf" "$tmp/configs/bad-nginx/xray.conf"
cp "$tmp/configs/vless-ws-nginx/share.template" "$tmp/configs/bad-nginx/share.template"
printf 'FAIL_NGINX\n' >"$tmp/configs/bad-nginx/nginx.conf"
export BLACKOUT_NGINX_FAIL_ON_BAD_CONFIG=1
if bo_config_switch bad-nginx >/dev/null 2>&1; then
  echo "bad nginx config accepted" >&2
  exit 1
fi
unset BLACKOUT_NGINX_FAIL_ON_BAD_CONFIG
[ "$(cat "$tmp/etc/nginx/sites-available/blackout")" = "$before_nginx" ]
[ "$(bo_setting_get profile)" = "vless-ws-nginx" ]

bo_setting_set domain 'bad;example.com'
if ( bo_config_switch vless-ws-nginx ) >/dev/null 2>&1; then
  echo "unsafe domain accepted" >&2
  exit 1
fi
bo_setting_set domain example.com

bo_setting_set ws_path '/bad path'
if ( bo_config_switch vless-ws-nginx ) >/dev/null 2>&1; then
  echo "unsafe ws_path accepted" >&2
  exit 1
fi
bo_setting_set ws_path /blackout

bo_cert_cmd change-domain new.example.com
[ "$(bo_setting_get domain)" = "new.example.com" ]

bo_cert_cmd issue admin@example.com
grep -q 'acme.sh --issue --standalone -d new.example.com' "$BLACKOUT_TEST_LOG"
grep -q "acme.sh --install-cert -d new.example.com --fullchain-file $tmp/etc/ssl/fullchain.pem --key-file $tmp/etc/ssl/privkey.pem" "$BLACKOUT_TEST_LOG"

bo_cert_cmd renew
grep -q 'acme.sh --renew -d new.example.com --force' "$BLACKOUT_TEST_LOG"

starts_before="$(grep -c 'systemctl start nginx' "$BLACKOUT_TEST_LOG")"
export BLACKOUT_ACME_FAIL_ISSUE=1
set +e
bo_cert_cmd issue admin@example.com >/dev/null 2>&1
issue_status=$?
set -e
if [ "$issue_status" -eq 0 ]; then
  echo "failed issue returned success" >&2
  exit 1
fi
[ "$issue_status" -eq 42 ]
unset BLACKOUT_ACME_FAIL_ISSUE
starts_after="$(grep -c 'systemctl start nginx' "$BLACKOUT_TEST_LOG")"
[ "$starts_after" -gt "$starts_before" ]

export BLACKOUT_ACME_SKIP_ISSUE=1
bo_cert_cmd issue admin@example.com
unset BLACKOUT_ACME_SKIP_ISSUE
grep -q "acme.sh --install-cert -d new.example.com --fullchain-file $tmp/etc/ssl/fullchain.pem --key-file $tmp/etc/ssl/privkey.pem" "$BLACKOUT_TEST_LOG"

starts_before="$starts_after"
export BLACKOUT_ACME_FAIL_RENEW=1
set +e
bo_cert_cmd renew >/dev/null 2>&1
renew_status=$?
set -e
if [ "$renew_status" -eq 0 ]; then
  echo "failed renew returned success" >&2
  exit 1
fi
[ "$renew_status" -eq 43 ]
unset BLACKOUT_ACME_FAIL_RENEW
starts_after="$(grep -c 'systemctl start nginx' "$BLACKOUT_TEST_LOG")"
[ "$starts_after" -gt "$starts_before" ]
