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
bo_xray_add_user() {
  bo_xray_events="${bo_xray_events}add:$1:$2:$3"$'\n'
}
bo_xray_remove_user() {
  bo_xray_events="${bo_xray_events}remove:$1"$'\n'
}
bo_xray_user_stats() {
  printf 'stat: user>>>aiman>>>traffic>>>uplink value: 42\n'
}

bo_db_init

bo_user_add aiman secret 00000000-0000-0000-0000-000000000001 4102444800
bo_db_user_status aiman | grep -qx active
printf '%s' "$bo_xray_events" | grep -qx 'add:aiman:00000000-0000-0000-0000-000000000001:0'

bo_user_lock aiman
bo_db_user_status aiman | grep -qx locked
printf '%s' "$bo_xray_events" | grep -qx 'remove:aiman'

bo_user_unlock aiman
bo_db_user_status aiman | grep -qx active

bo_setting_set profile vless-ws-nginx
bo_setting_set domain vpn.example
bo_setting_set ws_path /vless
bo_user_link aiman | grep -qx 'vless://00000000-0000-0000-0000-000000000001@vpn.example:443?type=ws&security=tls&path=/vless&host=vpn.example#aiman'

bo_user_online | grep -q 'aiman'

bo_db_user_insert expired secret 00000000-0000-0000-0000-000000000002 expired@example 0 active 100 101
bo_user_expire | grep -qx expired
bo_db_user_status expired | grep -qx expired

bo_xray_add_user() {
  return 1
}
if bo_user_add failing secret 00000000-0000-0000-0000-000000000003 4102444800; then
  echo "add succeeded despite xray failure" >&2
  exit 1
fi
bo_db_user_status failing | grep -qx locked

bo_user_remove aiman
[ -z "$(bo_db_user_status aiman)" ]
