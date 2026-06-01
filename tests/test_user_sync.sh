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

bo_db_init
bo_setting_set active_inbound vless

bo_xray_events=""
bo_xray_api() {
  case "${1:-}" in
    adu)
      python3 - "$2" >>"$BLACKOUT_ETC_DIR/events" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as config_file:
    config = json.load(config_file)

client = config["inbounds"][0]["settings"]["clients"][0]
print(f"{client['email']} {client['id']} {client['level']}")
PY
      ;;
    *)
      return 1
      ;;
  esac
}

bo_db_user_insert active1 secret 00000000-0000-0000-0000-000000000031 active1@example 0 active 100 4102444800
bo_db_user_insert active2 secret 00000000-0000-0000-0000-000000000032 active2@example 3 active 100 4102444800
bo_db_user_insert locked secret 00000000-0000-0000-0000-000000000033 locked@example 0 locked 100 4102444800
bo_db_user_insert expired secret 00000000-0000-0000-0000-000000000034 expired@example 0 active 100 101

bo_user_sync_active_to_xray
grep -qx 'active1 00000000-0000-0000-0000-000000000031 0' "$BLACKOUT_ETC_DIR/events"
grep -qx 'active2 00000000-0000-0000-0000-000000000032 3' "$BLACKOUT_ETC_DIR/events"
if grep -q '^locked ' "$BLACKOUT_ETC_DIR/events" || grep -q '^expired ' "$BLACKOUT_ETC_DIR/events"; then
  echo "inactive user replayed" >&2
  exit 1
fi

bo_xray_api() {
  return 1
}
if bo_user_sync_active_to_xray >/dev/null 2>&1; then
  echo "sync succeeded despite xray failure" >&2
  exit 1
fi
