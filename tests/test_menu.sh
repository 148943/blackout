#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLACKOUT_LIB_DIR="$ROOT_DIR/lib"
BLACKOUT_TUI_TEST=1
BLACKOUT_TUI_ROWS=40
BLACKOUT_TUI_COLS=120
BLACKOUT_TUI_NOW='2026-06-21 12:00:00'
BLACKOUT_TUI_HOSTNAME='test-host'
BLACKOUT_VERSION='test-version'
NO_COLOR=1
refresh_count=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
events_file="$tmp/events"
: >"$events_file"

. "$ROOT_DIR/lib/common.sh"
. "$ROOT_DIR/lib/tui.sh"

bo_status_cmd() {
  refresh_count=$((refresh_count + 1))
  printf 'xray service: ok\n'
  printf 'xray api: ok\n'
  printf 'nginx service: ok\n'
  printf 'nginx config: ok\n'
  printf 'database: ok\n'
  printf 'config profile: ok\n'
  printf 'user api: disabled\n'
  printf 'overall: usable\n'
}
bo_setting_get() {
  case "$1" in
    profile) printf 'default\n' ;;
    domain) printf 'vpn.example\n' ;;
  esac
}
bo_db_query() {
  printf '3\n'
}
bo_db_users_rows() {
  printf 'aiman\tuuid-1\t0\tactive\t1700000000\t4102444800\t1700000000\n'
  printf 'locked\tuuid-2\t0\tlocked\t1700000000\t4102444800\t1700000000\n'
}
bo_user_cmd() { printf 'user:%s\n' "$*" >>"$events_file"; }
bo_user_add() { printf 'user:add:%s:%s:%s\n' "$1" "$2" "$3" >>"$events_file"; }
bo_user_generate_uuid() { printf 'generated-uuid\n'; }
bo_expiry_epoch() { printf '4102444800\n'; }
bo_user_modify_duration() { printf 'user:modify:%s:%s\n' "$1" "$2" >>"$events_file"; }
bo_xray_cmd() {
  printf 'xray:%s\n' "$*" >>"$events_file"
  [ "${1:-}" != current ] || printf 'Xray 26.6.1\n'
}
bo_cert_cmd() { printf 'cert:%s\n' "$*" >>"$events_file"; }
bo_config_list() { printf 'default\ncustom\n'; }
bo_config_current() { printf 'default\n'; }
bo_config_cmd() { printf 'config:%s\n' "$*" >>"$events_file"; }
bo_api_control_cmd() {
  printf 'api:%s\n' "$*" >>"$events_file"
  if [ "${BLACKOUT_TEST_API_STATUS_INACTIVE:-0}" = 1 ] && [ "${1:-}" = status ]; then
    printf 'blackout-api.service inactive\n'
    return 3
  fi
}
bo_update_cmd() { printf 'update:%s\n' "$*" >>"$events_file"; }
bo_cert_status() {
  printf 'domain: vpn.example\nstatus: ok\n'
}
bo_update_check() {
  printf 'status: installed version is latest\n'
}

. "$ROOT_DIR/lib/menu.sh"

bo_menu_init
frame="$(bo_menu_render)"
[ "$(wc -l <<<"$frame")" -le "$BLACKOUT_TUI_ROWS" ]
grep -q 'BLACKOUT' <<<"$frame"
grep -q 'test-version' <<<"$frame"
grep -q 'test-host' <<<"$frame"
grep -q 'Blackout > Dashboard' <<<"$frame"
for label in XRAY NGINX DATABASE CERTIFICATE API PROFILE USERS UPDATE; do
  grep -q "$label" <<<"$frame"
done
grep -q 'Navigate' <<<"$frame"
grep -q 'Refresh' <<<"$frame"
grep -q 'Help' <<<"$frame"
grep -q 'Quit' <<<"$frame"
if grep -q '1) Status' <<<"$frame"; then
  echo 'legacy numbered menu rendered' >&2
  exit 1
fi
compact_frame="$(BLACKOUT_TUI_ROWS=28 BLACKOUT_TUI_COLS=70 bo_menu_render)"
[ "$(wc -l <<<"$compact_frame")" -le 28 ]
grep -q 'XRAY' <<<"$compact_frame"
grep -q 'UPDATE' <<<"$compact_frame"

[ "$BO_MENU_SCREEN" = dashboard ]
[ "$BO_MENU_SELECTION" = 0 ]
bo_menu_handle_key down
[ "$BO_MENU_SELECTION" = 1 ]
bo_menu_handle_key enter
[ "$BO_MENU_SCREEN" = users ]
grep -q 'Blackout > Users' <<<"$(bo_menu_render)"
bo_menu_handle_key back
[ "$BO_MENU_SCREEN" = dashboard ]

BO_MENU_SELECTION=5
before="$refresh_count"
bo_menu_handle_key other
[ "$refresh_count" = "$before" ]
bo_menu_handle_key refresh
[ "$refresh_count" -gt "$before" ]
[ "$BO_MENU_SELECTION" = 5 ]

bo_menu_handle_key help
[ "$BO_MENU_SHOW_HELP" = 1 ]
grep -q 'Keyboard shortcuts' <<<"$(bo_menu_render)"
bo_menu_handle_key back
[ "$BO_MENU_SHOW_HELP" = 0 ]

BO_MENU_SELECTION=99
bo_menu_tick
[ "$BO_MENU_SELECTION" = 6 ]

if ( BLACKOUT_TUI_TEST=0 bo_menu </dev/null >/dev/null 2>&1 ); then
  echo 'non-tty menu invocation accepted' >&2
  exit 1
fi

BO_MENU_ONLINE_USERS=$'aiman\t12\t100'
bo_menu_open users
users_frame="$(bo_menu_render)"
grep -q 'Add user' <<<"$users_frame"
grep -q 'aiman' <<<"$users_frame"
grep -q 'active' <<<"$users_frame"
grep -q 'online' <<<"$users_frame"
grep -q 'locked' <<<"$users_frame"
grep -q '2100-01-01' <<<"$users_frame"

BO_MENU_SELECTION=1
bo_menu_activate
[ "$BO_MENU_SCREEN" = user-detail ]
[ "$BO_MENU_SELECTED_USER" = aiman ]
detail_frame="$(bo_menu_render)"
grep -q 'Blackout > Users > aiman' <<<"$detail_frame"
grep -q 'Link' <<<"$detail_frame"
grep -q 'Modify duration' <<<"$detail_frame"
grep -q 'Lock' <<<"$detail_frame"
grep -q 'Remove' <<<"$detail_frame"

BLACKOUT_TUI_CONFIRM=no
BO_MENU_SELECTION=2
bo_menu_activate
if grep -q '^user:lock aiman$' "$events_file"; then
  echo 'lock ran after rejected confirmation' >&2
  exit 1
fi
BLACKOUT_TUI_CONFIRM=yes
bo_menu_activate
grep -q '^user:lock aiman$' "$events_file"
grep -q 'Lock user aiman' <<<"$BO_MENU_RESULT"

bo_menu_open xray
grep -q 'Xray 26.6.1' <<<"$(bo_menu_render)"
BO_MENU_SELECTION=0
BLACKOUT_TUI_CONFIRM=no
bo_menu_activate
if grep -q '^xray:install latest$' "$events_file"; then
  echo 'xray install ran after rejected confirmation' >&2
  exit 1
fi
BLACKOUT_TUI_CONFIRM=yes
bo_menu_activate
grep -q '^xray:install latest$' "$events_file"

bo_menu_open certs
grep -q 'vpn.example' <<<"$(bo_menu_render)"
BO_MENU_SELECTION=2
bo_menu_activate
grep -q '^cert:renew$' "$events_file"

bo_menu_open config
config_frame="$(bo_menu_render)"
grep -q 'default.*active' <<<"$config_frame"
grep -q 'custom' <<<"$config_frame"
BO_MENU_SELECTION=2
bo_menu_activate
grep -q '^config:switch custom$' "$events_file"

bo_menu_open api
grep -q 'disabled' <<<"$(bo_menu_render)"
BO_MENU_SELECTION=2
BLACKOUT_TEST_API_STATUS_INACTIVE=1
bo_menu_activate
unset BLACKOUT_TEST_API_STATUS_INACTIVE
grep -q '^api:status$' "$events_file"
grep -q 'API status' <<<"$BO_MENU_RESULT"
grep -q 'blackout-api.service inactive' <<<"$BO_MENU_RESULT"
if grep -q 'Failed: API status' <<<"$BO_MENU_RESULT"; then
  echo 'api status rendered inactive service as failed action' >&2
  exit 1
fi
BO_MENU_SELECTION=1
BLACKOUT_TUI_CONFIRM=no
bo_menu_activate
if grep -q '^api:disable$' "$events_file"; then
  echo 'api disable ran after rejected confirmation' >&2
  exit 1
fi
BLACKOUT_TUI_CONFIRM=yes
bo_menu_activate
grep -q '^api:disable$' "$events_file"

bo_menu_open update
grep -q 'test-version' <<<"$(bo_menu_render)"
BO_MENU_SELECTION=1
bo_menu_activate
grep -q '^update:run$' "$events_file"

input_values="$tmp/input-values"
printf 'new-user\n7d\n' >"$input_values"
bo_tui_input() { sed -n '1p' "$input_values"; sed -i '1d' "$input_values"; }
bo_menu_open users
BO_MENU_SELECTION=0
bo_menu_activate
grep -q '^user:add:new-user:generated-uuid:4102444800$' "$events_file"

unset BLACKOUT_TUI_CONFIRM

bo_status_cmd() {
  printf 'xray service: fail\n'
  printf 'overall: failed\n'
  return 1
}
bo_menu_init
[ "$(bo_menu_status_value overall)" = failed ]
[ "$BO_MENU_RUNNING" = 1 ]

loop_counter="$tmp/loop-counter"
tick_counter="$tmp/tick-counter"
printf '0\n' >"$loop_counter"
: >"$tick_counter"
bo_tui_read_key() {
  local count
  count="$(cat "$loop_counter")"
  count=$((count + 1))
  printf '%s\n' "$count" >"$loop_counter"
  if [ "$count" -eq 1 ]; then
    return 1
  fi
  printf 'q'
}
bo_menu_tick() {
  printf 'tick\n' >>"$tick_counter"
}
bo_menu >/dev/null
if [ -s "$tick_counter" ]; then
  echo 'menu refreshed automatically after input timeout' >&2
  exit 1
fi
