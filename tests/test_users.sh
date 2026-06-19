#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLACKOUT_LIB_DIR="$ROOT_DIR/lib"
BLACKOUT_CONFIG_DIR="$ROOT_DIR/configs"
BLACKOUT_ETC_DIR="$(mktemp -d)"
tmpdb="$(mktemp)"
trap 'rm -rf "$BLACKOUT_ETC_DIR" "$tmpdb"' EXIT
BLACKOUT_DB="$tmpdb"
BLACKOUT_XRAY_CONFIG="$BLACKOUT_ETC_DIR/xray.json"

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

inbound = config["inbounds"][0]
client = inbound["settings"]["clients"][0]
assert inbound["tag"] in {"vless", "xhttp"}
assert inbound["listen"] == "127.0.0.1"
assert inbound["port"] == 1
assert client["id"] == "00000000-0000-0000-0000-000000000001"
assert client["email"] == "aiman"
assert client["level"] == 0
PY
      tag="$(python3 - "$2" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as config_file:
    print(json.load(config_file)["inbounds"][0]["tag"])
PY
)"
      bo_xray_events="${bo_xray_events}adu:$tag:$2"$'\n'
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
  if [ "${BLACKOUT_TEST_STATS_FAIL:-0}" = "1" ]; then
    return 1
  fi
  bo_xray_events="${bo_xray_events}stats:$1"$'\n'
  if [ -n "${BLACKOUT_TEST_STATS_LOG:-}" ]; then
    printf '%s\n' "$1" >>"$BLACKOUT_TEST_STATS_LOG"
  fi
  local bump=0 calls=0
  if [ -f "${BLACKOUT_TEST_ONLINE_COUNTER:-}" ]; then
    calls="$(cat "$BLACKOUT_TEST_ONLINE_COUNTER")"
  fi
  calls="$((calls + 1))"
  printf '%s\n' "$calls" >"$BLACKOUT_TEST_ONLINE_COUNTER"
  if [ "${BLACKOUT_TEST_ONLINE_BUMP:-0}" = "1" ] && [ "$calls" -gt 1 ]; then
    bump=4096
  fi
  cat <<JSON
{
  "stat": [
    {
      "name": "user>>>$1>>>traffic>>>downlink",
      "value": $((2270428 + bump))
    },
    {
      "name": "user>>>$1>>>traffic>>>uplink",
      "value": $((851737 + bump))
    }
  ]
}
JSON
}

bo_db_init
cat >"$BLACKOUT_XRAY_CONFIG" <<'JSON'
{
  "inbounds": [
    {"tag": "api", "protocol": "dokodemo-door"},
    {"tag": "vless", "protocol": "vless", "settings": {"clients": []}},
    {"tag": "xhttp", "protocol": "vless", "settings": {"clients": []}}
  ]
}
JSON

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
bo_db_users_rows | grep -q $'^aiman\t00000000-0000-0000-0000-000000000001\t0\tactive\t'
[ "$(bo_db_users_rows | awk -F '\t' 'NR == 1 { print NF }')" = 7 ]
bo_db_user_insert zulu 00000000-0000-0000-0000-000000000013 zulu@example 0 locked 100 4102444800
[ "$(bo_db_users_rows | cut -f1 | paste -sd, -)" = "aiman,zulu" ]
bo_db_user_delete zulu
printf '%s' "$bo_xray_events" | grep -Eq '^adu:'
printf '%s' "$bo_xray_events" | grep -Eq '^adu:vless:'
printf '%s' "$bo_xray_events" | grep -Eq '^adu:xhttp:'
if [ "$(printf '%s' "$bo_xray_events" | grep -c '^adu:')" != 2 ]; then
  echo "user was not added to all xray inbounds" >&2
  exit 1
fi
adu_file="$(printf '%s' "$bo_xray_events" | sed -n 's/^adu:[^:]*://p' | head -n 1)"
[ -n "$adu_file" ]
[ ! -e "$adu_file" ]

bo_user_modify_duration aiman 7d
after_expiry="$(bo_db_user_get aiman | cut -f7)"
now="$(date +%s)"
[ "$after_expiry" -ge "$((now + 604790))" ]
[ "$after_expiry" -le "$((now + 604810))" ]
printf '12h\n' | bo_user_modify aiman
prompt_expiry="$(bo_db_user_get aiman | cut -f7)"
now="$(date +%s)"
[ "$prompt_expiry" -ge "$((now + 43190))" ]
[ "$prompt_expiry" -le "$((now + 43210))" ]
if bo_user_modify_duration ghost 7d >/dev/null 2>&1; then
  echo "unknown user duration update succeeded" >&2
  exit 1
fi
if bo_user_modify_duration aiman invalid >/dev/null 2>&1; then
  echo "invalid duration update succeeded" >&2
  exit 1
fi

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
printf '%s' "$bo_xray_events" | grep -qx 'rmu -tag=xhttp aiman'

bo_user_unlock aiman
bo_db_user_status aiman | grep -qx active
if [ "$(printf '%s' "$bo_xray_events" | grep -c '^adu:')" != 4 ]; then
  echo "user was not unlocked into all xray inbounds" >&2
  exit 1
fi

bo_setting_set profile default
bo_setting_set domain '*.vpn.example'
bo_user_link aiman >"$BLACKOUT_ETC_DIR/default-links.out"
grep -qx 'VLESS WS TLS:' "$BLACKOUT_ETC_DIR/default-links.out"
grep -qx 'vless://00000000-0000-0000-0000-000000000001@vpn.example:443?type=ws&security=tls&path=/vless&host=vpn.example#aiman' "$BLACKOUT_ETC_DIR/default-links.out"
if grep -q 'VLESS WS HTTP' "$BLACKOUT_ETC_DIR/default-links.out"; then
  echo "default HTTP share link rendered" >&2
  exit 1
fi
if grep -q '\*\.vpn.example' "$BLACKOUT_ETC_DIR/default-links.out"; then
  echo "wildcard domain leaked into share link" >&2
  exit 1
fi
rm -f "$BLACKOUT_ETC_DIR/default-links.out"

BLACKOUT_CONFIG_DIR="$BLACKOUT_ETC_DIR/configs"
mkdir -p "$BLACKOUT_CONFIG_DIR/default"
cat >"$BLACKOUT_CONFIG_DIR/default/share.template" <<'TPL'
VLESS WS TLS
vless://{{UUID}}@{{DOMAIN}}:443?type=ws&security=tls&path=/vless&host={{DOMAIN}}#{{USERNAME}}

Clash Meta
vless://{{UUID}}@{{DOMAIN}}:443?type=ws&security=tls&path=/vless&host={{DOMAIN}}#{{USERNAME}}-clash
TPL
bo_user_link aiman >"$BLACKOUT_ETC_DIR/links.out"
grep -qx 'VLESS WS TLS:' "$BLACKOUT_ETC_DIR/links.out"
grep -qx 'Clash Meta:' "$BLACKOUT_ETC_DIR/links.out"
grep -qx 'vless://00000000-0000-0000-0000-000000000001@vpn.example:443?type=ws&security=tls&path=/vless&host=vpn.example#aiman' "$BLACKOUT_ETC_DIR/links.out"
grep -qx 'vless://00000000-0000-0000-0000-000000000001@vpn.example:443?type=ws&security=tls&path=/vless&host=vpn.example#aiman-clash' "$BLACKOUT_ETC_DIR/links.out"
bo_user_link_rows aiman >"$BLACKOUT_ETC_DIR/link-rows.out"
grep -qx $'VLESS WS TLS\tvless://00000000-0000-0000-0000-000000000001@vpn.example:443?type=ws&security=tls&path=/vless&host=vpn.example#aiman' "$BLACKOUT_ETC_DIR/link-rows.out"
grep -qx $'Clash Meta\tvless://00000000-0000-0000-0000-000000000001@vpn.example:443?type=ws&security=tls&path=/vless&host=vpn.example#aiman-clash' "$BLACKOUT_ETC_DIR/link-rows.out"
if grep -q '\*\.vpn.example' "$BLACKOUT_ETC_DIR/link-rows.out"; then
  echo "wildcard domain leaked into structured share links" >&2
  exit 1
fi

cat >"$BLACKOUT_CONFIG_DIR/default/share.template" <<'TPL'
vless://{{UUID}}@{{DOMAIN}}:443?type=ws&security=tls&path=/vless&host={{DOMAIN}}#{{USERNAME}}
TPL
bo_user_link_rows aiman | grep -qx $'\tvless://00000000-0000-0000-0000-000000000001@vpn.example:443?type=ws&security=tls&path=/vless&host=vpn.example#aiman'
bo_user_link aiman | grep -qx 'vless://00000000-0000-0000-0000-000000000001@vpn.example:443?type=ws&security=tls&path=/vless&host=vpn.example#aiman'

if bo_user_link_rows ghost >/dev/null 2>&1; then
  echo "unknown user structured link succeeded" >&2
  exit 1
fi
rm -rf "$BLACKOUT_CONFIG_DIR" "$BLACKOUT_ETC_DIR/links.out"
BLACKOUT_CONFIG_DIR="$ROOT_DIR/configs"

BLACKOUT_TEST_ONLINE_COUNTER="$BLACKOUT_ETC_DIR/online-counter"
printf '0\n' >"$BLACKOUT_TEST_ONLINE_COUNTER"
if [ -n "$(bo_user_online 0)" ]; then
  echo "idle user appeared online" >&2
  exit 1
fi
printf '0\n' >"$BLACKOUT_TEST_ONLINE_COUNTER"
BLACKOUT_TEST_ONLINE_BUMP=1 bo_user_online 0 | grep -qx 'aiman  status=online  delta=8.0 KiB  total=3.0 MiB'
printf '0\n' >"$BLACKOUT_TEST_ONLINE_COUNTER"
BLACKOUT_TEST_ONLINE_BUMP=1 bo_user_online_rows 0 | grep -qx $'aiman\t8192\t3130357'
if (bo_user_online_rows invalid >/dev/null 2>&1); then
  echo "invalid structured online sample succeeded" >&2
  exit 1
fi

if BLACKOUT_TEST_STATS_FAIL=1 bo_user_online_rows 0 >/dev/null 2>&1; then
  echo "structured online succeeded despite stats failure" >&2
  exit 1
fi
if BLACKOUT_TEST_STATS_FAIL=1 bo_user_online 0 >/dev/null 2>&1; then
  echo "human online succeeded despite stats failure" >&2
  exit 1
fi

bo_db_user_insert stale 00000000-0000-0000-0000-000000000006 stale@example 0 active 100 101
bo_xray_events=""
if bo_user_link stale >/dev/null 2>&1; then
  echo "expired active user received link" >&2
  exit 1
fi
printf '%s' "$bo_xray_events" | grep -qx 'rmu -tag=vless stale'
printf '%s' "$bo_xray_events" | grep -qx 'rmu -tag=xhttp stale'
bo_db_user_status stale | grep -qx expired

bo_db_user_insert stale_fail 00000000-0000-0000-0000-000000000008 stale_fail@example 0 active 100 101
bo_xray_api() {
  return 1
}
if bo_user_link_rows stale_fail >/dev/null 2>&1; then
  echo "expired active structured link succeeded despite remove failure" >&2
  exit 1
fi
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
BLACKOUT_TEST_STATS_LOG="$BLACKOUT_ETC_DIR/stats.log"
: >"$BLACKOUT_TEST_STATS_LOG"
bo_user_online 0 >/dev/null
grep -qx 'aiman' "$BLACKOUT_TEST_STATS_LOG"
if grep -q '^stale$' "$BLACKOUT_TEST_STATS_LOG"; then
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
printf '%s' "$bo_xray_events" | grep -qx 'rmu -tag=xhttp unlock_expired'
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
