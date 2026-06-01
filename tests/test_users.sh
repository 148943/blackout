#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLACKOUT_LIB_DIR="$ROOT_DIR/lib"
BLACKOUT_CONFIG_DIR="$ROOT_DIR/configs"
BLACKOUT_ETC_DIR="$(mktemp -d)"
tmpdb="$(mktemp)"
trap 'rm -rf "$BLACKOUT_ETC_DIR" "$tmpdb"' EXIT
BLACKOUT_DB="$tmpdb"

. "$ROOT_DIR/lib/db.sh"
. "$ROOT_DIR/lib/users.sh"

bo_xray_events=""
bo_xray_api() {
  case "${1:-}" in
    adu)
      [ -f "${2:-}" ]
      python3 - "$2" <<'PY' || return 1
import json
import sys

with open(sys.argv[1], encoding="utf-8") as config_file:
    config = json.load(config_file)

client = config["inbounds"][0]["settings"]["clients"][0]
assert config["inbounds"][0]["tag"] == "vless"
assert config["inbounds"][0]["listen"] == "127.0.0.1"
assert config["inbounds"][0]["port"] == 1
assert client["id"] == "00000000-0000-0000-0000-000000000001"
assert client["email"] == "aiman"
assert client["level"] == 0
PY
      bo_xray_events="${bo_xray_events}adu:$2"$'\n'
      ;;
    rmu)
      bo_xray_events="${bo_xray_events}$*"$'\n'
      ;;
    *)
      bo_xray_events="${bo_xray_events}$*"$'\n'
      ;;
  esac
}
bo_xray_user_stats() {
  bo_xray_events="${bo_xray_events}stats:$1"$'\n'
  printf 'stat: user>>>%s>>>traffic>>>uplink value: 42\n' "$1"
}

bo_db_init
bo_setting_set active_inbound vless

for cmd in remove modify lock unlock link; do
  output="$(
    if (
      if bo_user_cmd "$cmd" 2>/dev/null; then
        echo "missing $cmd arg succeeded" >&2
        exit 1
      fi
      printf 'survived\n'
    ); then
      :
    else
      echo "missing $cmd arg exited shell" >&2
      exit 1
    fi
  )"
  [ "$output" = survived ]
done

bo_user_add aiman 00000000-0000-0000-0000-000000000001 4102444800
bo_db_user_status aiman | grep -qx active
bo_user_list | grep -q '2100-01-01 00:00:00 UTC'
printf '%s' "$bo_xray_events" | grep -Eq '^adu:'
adu_file="$(printf '%s' "$bo_xray_events" | sed -n 's/^adu://p' | head -n 1)"
[ -n "$adu_file" ]
[ ! -e "$adu_file" ]

before_events="$bo_xray_events"
if bo_user_add aiman 00000000-0000-0000-0000-000000000004 4102444800 2>/dev/null; then
  echo "duplicate add succeeded" >&2
  exit 1
fi
[ "$bo_xray_events" = "$before_events" ]

before_events="$bo_xray_events"
if bo_user_add past 00000000-0000-0000-0000-000000000005 100 2>/dev/null; then
  echo "past expiry add succeeded" >&2
  exit 1
fi
[ "$bo_xray_events" = "$before_events" ]
if bo_user_add invalid 00000000-0000-0000-0000-000000000007 nope 2>/dev/null; then
  echo "invalid expiry add succeeded" >&2
  exit 1
fi
[ "$bo_xray_events" = "$before_events" ]
if bo_user_add badlevel 00000000-0000-0000-0000-000000000011 4102444800 '0);DROP TABLE users;--' 2>/dev/null; then
  echo "malicious level add succeeded" >&2
  exit 1
fi
[ "$bo_xray_events" = "$before_events" ]

if bo_db_user_insert injected 00000000-0000-0000-0000-000000000012 injected@example '0);DROP TABLE users;--' active 100 200 2>/dev/null; then
  echo "malicious db insert succeeded" >&2
  exit 1
fi
sqlite3 "$BLACKOUT_DB" "select name from sqlite_master where type='table' and name='users';" | grep -qx users

if bo_user_lock ghost 2>/dev/null; then
  echo "ghost lock succeeded" >&2
  exit 1
fi
[ "$bo_xray_events" = "$before_events" ]

if bo_user_remove ghost 2>/dev/null; then
  echo "ghost remove succeeded" >&2
  exit 1
fi
[ "$bo_xray_events" = "$before_events" ]

bo_user_lock aiman
bo_db_user_status aiman | grep -qx locked
printf '%s' "$bo_xray_events" | grep -qx 'rmu -tag=vless aiman'

bo_user_unlock aiman
bo_db_user_status aiman | grep -qx active

bo_setting_set profile vless-ws-nginx
bo_setting_set domain vpn.example
bo_setting_set ws_path /vless
bo_user_link aiman | grep -qx 'vless://00000000-0000-0000-0000-000000000001@vpn.example:443?type=ws&security=tls&path=/vless&host=vpn.example#aiman'

bo_user_online | grep -q 'aiman'

bo_db_user_insert stale 00000000-0000-0000-0000-000000000006 stale@example 0 active 100 101
bo_xray_events=""
if bo_user_link stale >/dev/null 2>&1; then
  echo "expired active user received link" >&2
  exit 1
fi
printf '%s' "$bo_xray_events" | grep -qx 'rmu -tag=vless stale'
bo_db_user_status stale | grep -qx expired

bo_db_user_insert stale_fail 00000000-0000-0000-0000-000000000008 stale_fail@example 0 active 100 101
bo_xray_api() {
  return 1
}
if bo_user_link stale_fail >/dev/null 2>&1; then
  echo "expired active link succeeded despite remove failure" >&2
  exit 1
fi
bo_db_user_status stale_fail | grep -qx active
bo_db_user_set_status stale_fail locked

bo_xray_api() {
  bo_xray_events="${bo_xray_events}$*"$'\n'
}
bo_xray_events=""
bo_user_online | grep -q 'aiman'
if printf '%s' "$bo_xray_events" | grep -q 'stats:stale'; then
  echo "expired active user checked online" >&2
  exit 1
fi

bo_db_user_insert unlock_expired 00000000-0000-0000-0000-000000000009 unlock_expired@example 0 active 100 101
bo_xray_events=""
if bo_user_unlock unlock_expired >/dev/null 2>&1; then
  echo "expired active unlock succeeded" >&2
  exit 1
fi
printf '%s' "$bo_xray_events" | grep -qx 'rmu -tag=vless unlock_expired'
bo_db_user_status unlock_expired | grep -qx expired

bo_db_user_insert unlock_fail 00000000-0000-0000-0000-000000000010 unlock_fail@example 0 active 100 101
bo_xray_api() {
  return 1
}
if bo_user_unlock unlock_fail >/dev/null 2>&1; then
  echo "expired active unlock succeeded despite remove failure" >&2
  exit 1
fi
bo_db_user_status unlock_fail | grep -qx active
bo_db_user_set_status unlock_fail locked

bo_xray_api() {
  bo_xray_events="${bo_xray_events}$*"$'\n'
}
bo_db_user_insert expired 00000000-0000-0000-0000-000000000002 expired@example 0 active 100 101
bo_user_expire | grep -qx expired
bo_db_user_status expired | grep -qx expired

bo_xray_api() {
  return 1
}
if bo_user_add failing 00000000-0000-0000-0000-000000000003 4102444800; then
  echo "add succeeded despite xray failure" >&2
  exit 1
fi
bo_db_user_status failing | grep -qx locked

bo_xray_api() {
  bo_xray_events="${bo_xray_events}$*"$'\n'
}
bo_user_remove aiman
[ -z "$(bo_db_user_status aiman)" ]
