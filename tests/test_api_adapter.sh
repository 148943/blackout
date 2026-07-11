#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLACKOUT_LIB_DIR="$ROOT_DIR/lib"
BLACKOUT_CONFIG_DIR="$ROOT_DIR/configs"
BLACKOUT_ETC_DIR="$(mktemp -d)"
tmpdb="$(mktemp)"
trap 'rm -rf "$BLACKOUT_ETC_DIR" "$tmpdb"' EXIT
BLACKOUT_DB="$tmpdb"
BLACKOUT_TEST_ONLINE_COUNTER="$BLACKOUT_ETC_DIR/online-counter"
BLACKOUT_TEST_ONLINE_BUMP=1

. "$ROOT_DIR/lib/db.sh"
. "$ROOT_DIR/lib/users.sh"
. "$ROOT_DIR/lib/api.sh"

bo_xray_events=""
bo_xray_api() {
  case "${1:-}" in
    adu)
      bo_xray_events="${bo_xray_events}adu"$'\n'
      ;;
    rmu)
      bo_xray_events="${bo_xray_events}$*"$'\n'
      ;;
  esac
}

bo_xray_user_stats() {
  local username="$1" calls=0 bump=0
  if [ "${BLACKOUT_TEST_STATS_FAIL:-0}" = 1 ]; then
    return 1
  fi
  if [ -f "$BLACKOUT_TEST_ONLINE_COUNTER" ]; then
    calls="$(cat "$BLACKOUT_TEST_ONLINE_COUNTER")"
  fi
  calls="$((calls + 1))"
  printf '%s\n' "$calls" >"$BLACKOUT_TEST_ONLINE_COUNTER"
  if [ "$calls" -gt 1 ]; then
    bump=4096
  fi
  cat <<JSON
{"stat":[
{"name":"user>>>$username>>>traffic>>>downlink","value":$((2048 + bump))},
{"name":"user>>>$username>>>traffic>>>uplink","value":$((1024 + bump))}
]}
JSON
}

json_get() {
  python3 -c 'import json,sys; data=json.load(sys.stdin); cur=data
for part in sys.argv[1].split("."):
    cur=cur[int(part)] if isinstance(cur, list) else cur[part]
print(cur)' "$1"
}

expect_status() {
  local expected="$1"; shift
  set +e
  output="$("$@" 2>"$BLACKOUT_ETC_DIR/stderr")"
  status=$?
  set -e
  [ "$status" = "$expected" ] || {
    printf 'expected status %s, got %s for %s\nstdout=%s\nstderr=%s\n' \
      "$expected" "$status" "$*" "$output" "$(cat "$BLACKOUT_ETC_DIR/stderr")" >&2
    exit 1
  }
  printf '%s\n' "$output" | python3 -m json.tool >/dev/null
  printf '%s\n' "$output"
}

bo_db_init
bo_setting_set active_inbound vless
bo_setting_set domain '*.vpn.example'
bo_setting_set ws_path /

bo_db_users_rows_original="$(declare -f bo_db_users_rows)"
bo_db_users_rows() { return 1; }
out="$(expect_status 20 bo_api_cmd list)"
[ "$(printf '%s\n' "$out" | json_get error.code)" = backend_error ]
eval "$bo_db_users_rows_original"

out="$(bo_api_cmd create aiman 1d)"
[ "$(printf '%s\n' "$out" | json_get ok)" = True ]
[ "$(printf '%s\n' "$out" | json_get data.username)" = aiman ]
[ "$(printf '%s\n' "$out" | json_get data.status)" = active ]
[ "$(printf '%s\n' "$out" | json_get data.level)" = 0 ]
printf '%s\n' "$out" | json_get data.uuid | grep -Eq '^[0-9a-fA-F-]{36}$'

out="$(bo_api_cmd list)"
[ "$(printf '%s\n' "$out" | json_get data.0.username)" = aiman ]
[ "$(printf '%s\n' "$out" | json_get data.0.email 2>/dev/null || true)" = "" ]

out="$(bo_api_cmd modify aiman 12h)"
[ "$(printf '%s\n' "$out" | json_get data.username)" = aiman ]

out="$(bo_api_cmd modify aiman never)"
[ "$(printf '%s\n' "$out" | json_get data.username)" = aiman ]
[ "$(bo_db_user_get aiman | cut -f7)" = "4102444800" ]

out="$(bo_api_cmd lock aiman)"
[ "$(printf '%s\n' "$out" | json_get data.status)" = locked ]

out="$(bo_api_cmd unlock aiman)"
[ "$(printf '%s\n' "$out" | json_get data.status)" = active ]

out="$(bo_api_cmd links aiman)"
[ "$(printf '%s\n' "$out" | json_get data.0.name)" = "VLESS WS TLS" ]
printf '%s\n' "$out" | json_get data.0.link | grep -q '@vpn.example:443'
if printf '%s\n' "$out" | grep -q '\*\.vpn.example'; then
  echo "wildcard domain leaked into API links" >&2
  exit 1
fi

out="$(bo_api_cmd online 0)"
[ "$(printf '%s\n' "$out" | json_get data.0.username)" = aiman ]
[ "$(printf '%s\n' "$out" | json_get data.0.delta_bytes)" = 8192 ]

out="$(expect_status 12 bo_api_cmd create aiman 1d)"
[ "$(printf '%s\n' "$out" | json_get error.code)" = conflict ]

out="$(expect_status 11 bo_api_cmd modify ghost 1d)"
[ "$(printf '%s\n' "$out" | json_get error.code)" = not_found ]

out="$(expect_status 10 bo_api_cmd create bad)"
[ "$(printf '%s\n' "$out" | json_get error.code)" = invalid_request ]

out="$(expect_status 10 bo_api_cmd create zulu 0d)"
[ "$(printf '%s\n' "$out" | json_get error.code)" = invalid_request ]

BLACKOUT_TEST_STATS_FAIL=1
out="$(expect_status 20 bo_api_cmd online 0)"
[ "$(printf '%s\n' "$out" | json_get error.code)" = backend_error ]
unset BLACKOUT_TEST_STATS_FAIL

out="$(bo_api_cmd remove aiman)"
[ "$(printf '%s\n' "$out" | json_get data.username)" = aiman ]
if bo_db_user_get aiman | grep -q aiman; then
  echo "remove did not delete user" >&2
  exit 1
fi

out="$(expect_status 11 bo_api_cmd remove aiman)"
[ "$(printf '%s\n' "$out" | json_get error.code)" = not_found ]

out="$(expect_status 10 bo_api_cmd unknown)"
[ "$(printf '%s\n' "$out" | json_get error.code)" = invalid_request ]

out="$(expect_status 11 bo_api_user_success ghost)"
[ "$(printf '%s\n' "$out" | json_get error.code)" = not_found ]

bo_user_add failread 00000000-0000-0000-0000-000000000021 4102444800
bo_db_user_get_original="$(declare -f bo_db_user_get)"
bo_db_user_get() { return 1; }
out="$(expect_status 20 bo_api_cmd lock failread)"
[ "$(printf '%s\n' "$out" | json_get error.code)" = backend_error ]
eval "$bo_db_user_get_original"
