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
user_status_file="$tmp/user-status"
expired_status_file="$tmp/expired-status"
api_status_file="$tmp/api-status"
: >"$events_file"
printf 'active\n' >"$user_status_file"
printf 'expired\n' >"$expired_status_file"
printf 'disabled\n' >"$api_status_file"

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
  printf 'user api: %s\n' "$(cat "$api_status_file")"
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
  printf 'aiman\tuuid-1\t0\t%s\t1700000000\t4102444800\t1700000000\n' "$(cat "$user_status_file")"
  printf 'locked\tuuid-2\t0\tlocked\t1700000000\t4102444800\t1700000000\n'
  printf 'expired\tuuid-3\t0\t%s\t1700000000\t1700000001\t1700000000\n' "$(cat "$expired_status_file")"
}
bo_user_cmd() {
  printf 'user:%s\n' "$*" >>"$events_file"
  case "$1" in
    lock) printf 'locked\n' >"$user_status_file" ;;
    unlock) printf 'active\n' >"$user_status_file" ;;
  esac
}
bo_user_add() { printf 'user:add:%s:%s:%s\n' "$1" "$2" "$3" >>"$events_file"; }
bo_user_generate_uuid() { printf 'generated-uuid\n'; }
bo_expiry_epoch() { printf '4102444800\n'; }
bo_user_modify_duration() {
  printf 'user:modify:%s:%s\n' "$1" "$2" >>"$events_file"
  [ "$1" != expired ] || printf 'active\n' >"$expired_status_file"
}
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
  case "${1:-}" in
    enable) printf 'ok\n' >"$api_status_file" ;;
    disable) printf 'disabled\n' >"$api_status_file" ;;
  esac
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
grep -q 'Blackout > Dashboard' <<<"$frame"
if grep -Eq 'BLACKOUT.*test-version.*test-host' <<<"$frame" || grep -q '21 Jun 2026' <<<"$frame"; then
  echo 'dashboard rendered header metadata' >&2
  exit 1
fi
if grep -q '2026-06-21' <<<"$frame"; then
  echo 'menu header rendered ISO date' >&2
  exit 1
fi
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

bo_update_repo() { printf 'https://example.invalid/blackout.git\n'; }
bo_update_branch() { printf 'master\n'; }
bo_update_remote_version() { printf '%s\n' "$BLACKOUT_TEST_REMOTE_VERSION"; }
BLACKOUT_VERSION='b803562f475f9e4ea84699c2b5772462156ed03d'
BLACKOUT_TEST_REMOTE_VERSION="$BLACKOUT_VERSION"
update_summary="$(bo_menu_update_summary)"
[ "$update_summary" = $'b803562f475f\tlatest' ]
update_card="$(NO_COLOR=0 bo_tui_card UPDATE b803562f475 latest 24)"
grep -Fq $'\033[32m' <<<"$update_card"
BLACKOUT_TEST_REMOTE_VERSION='cf5f550795e1d25cff132368d6072b32da27ec05'
update_summary="$(bo_menu_update_summary)"
[ "$update_summary" = $'b803562f475f\twarning' ]
BLACKOUT_VERSION='test-version'
unset BLACKOUT_TEST_REMOTE_VERSION
unset -f bo_update_repo bo_update_branch bo_update_remote_version

certificate_file="$tmp/fullchain.pem"
printf 'certificate\n' >"$certificate_file"
openssl() {
  case "$*" in
    *-enddate*) printf 'notAfter=Jan 12 12:00:00 2026 GMT\n' ;;
    *-checkend*) return 0 ;;
  esac
}
certificate_summary="$(BLACKOUT_SSL_FULLCHAIN="$certificate_file" bo_menu_certificate_summary)"
grep -q '^12 Jan 2026' <<<"$certificate_summary"
unset -f openssl

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
if grep -Eq 'BLACKOUT.*test-version.*test-host' <<<"$users_frame" || grep -q '21 Jun 2026' <<<"$users_frame"; then
  echo 'users page rendered header metadata' >&2
  exit 1
fi
grep -q 'Add user' <<<"$users_frame"
grep -q 'aiman' <<<"$users_frame"
grep -q 'active' <<<"$users_frame"
grep -q 'online' <<<"$users_frame"
grep -q 'locked' <<<"$users_frame"
grep -q 'expired' <<<"$users_frame"
grep -q '1 Jan 2100' <<<"$users_frame"
if grep -q '2100-01-01' <<<"$users_frame"; then
  echo 'user expiry rendered ISO date' >&2
  exit 1
fi

BO_MENU_SELECTION=1
bo_menu_activate
[ "$BO_MENU_SCREEN" = user-detail ]
[ "$BO_MENU_SELECTED_USER" = aiman ]
detail_frame="$(bo_menu_render)"
if grep -Eq 'BLACKOUT.*test-version.*test-host' <<<"$detail_frame" || grep -q '21 Jun 2026' <<<"$detail_frame"; then
  echo 'user detail page rendered header metadata' >&2
  exit 1
fi
grep -q 'Blackout > Users > aiman' <<<"$detail_frame"
grep -q 'Link' <<<"$detail_frame"
grep -q 'Modify duration' <<<"$detail_frame"
grep -q 'Lock' <<<"$detail_frame"
grep -q 'Remove' <<<"$detail_frame"

original_flush="$(declare -f bo_tui_flush_input 2>/dev/null || true)"
flush_counter="$tmp/flush-counter"
: >"$flush_counter"
bo_tui_flush_input() { printf 'flush\n' >>"$flush_counter"; }
BO_MENU_SELECTION=0
bo_menu_activate
[ "$(wc -l <"$flush_counter")" -eq 1 ]
grep -q '^user:link aiman$' "$events_file"
grep -q 'Completed: Links for aiman' <<<"$BO_MENU_RESULT"
if grep -q '^user:modify:aiman:' "$events_file"; then
  echo 'Link action jumped to Modify duration' >&2
  exit 1
fi
[ "$BO_MENU_SCREEN" = user-detail ]
[ "$BO_MENU_SELECTION" -eq 0 ]
eval "$original_flush"

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
[ "$BO_MENU_SELECTED_USER_STATUS" = locked ]
grep -qx 'Unlock' <<<"$(bo_menu_rows | sed -n '3p')"

BO_MENU_RESULT=""
BO_MENU_SELECTION=2
bo_menu_activate
grep -q '^user:unlock aiman$' "$events_file"
grep -q 'Unlock user aiman' <<<"$BO_MENU_RESULT"
[ "$BO_MENU_SELECTED_USER_STATUS" = active ]
grep -qx 'Lock' <<<"$(bo_menu_rows | sed -n '3p')"

BO_MENU_RESULT=""
BO_MENU_SELECTION=3
bo_menu_open users
BO_MENU_SELECTION=3
bo_menu_activate
[ "$BO_MENU_SCREEN" = user-detail ]
[ "$BO_MENU_SELECTED_USER" = expired ]
[ "$BO_MENU_SELECTED_USER_STATUS" = expired ]
expired_rows="$(bo_menu_rows)"
grep -q 'Modify duration' <<<"$expired_rows"
if grep -q '^Unlock$' <<<"$expired_rows"; then
  echo 'expired user detail showed unlock action' >&2
  exit 1
fi
grep -qx 'Remove' <<<"$(bo_menu_rows | sed -n '3p')"
BO_MENU_SELECTION=1
bo_menu_activate
grep -q '^user:modify:expired:30d$' "$events_file"
[ "$BO_MENU_SELECTED_USER_STATUS" = active ]
grep -qx 'Lock' <<<"$(bo_menu_rows | sed -n '3p')"

BO_MENU_RESULT=""
bo_menu_open users
BO_MENU_SELECTION=1
bo_menu_activate
BO_MENU_RESULT=""
BO_MENU_SELECTION=3
BLACKOUT_TUI_CONFIRM=yes
bo_menu_activate
unset BLACKOUT_TUI_CONFIRM
grep -q '^user:remove aiman$' "$events_file"
[ "$BO_MENU_SCREEN" = users ]
grep -q 'Add user' <<<"$(bo_menu_render)"

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
api_frame="$(bo_menu_render)"
grep -q 'API state: disabled' <<<"$api_frame"
grep -q 'Enable' <<<"$api_frame"
if grep -q 'Disable' <<<"$api_frame"; then
  echo 'api menu showed Disable while disabled' >&2
  exit 1
fi
BO_MENU_SELECTION=1
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
BLACKOUT_TUI_CONFIRM=yes
bo_menu_handle_key up
bo_menu_handle_key enter
unset BLACKOUT_TUI_CONFIRM
if grep -q '^api:disable$' "$events_file" || grep -q '^api:enable$' "$events_file"; then
  echo 'api result panel allowed hidden enable/disable action' >&2
  exit 1
fi
[ -z "$BO_MENU_RESULT" ]

BO_MENU_SELECTION=0
bo_menu_activate
grep -q '^api:enable$' "$events_file"
[ "$(bo_menu_status_value 'user api')" = ok ]
grep -qx 'Disable' <<<"$(bo_menu_rows | sed -n '1p')"

BO_MENU_RESULT=""
BO_MENU_SELECTION=0
BLACKOUT_TUI_CONFIRM=no
bo_menu_activate
if grep -q '^api:disable$' "$events_file"; then
  echo 'api disable ran after rejected confirmation' >&2
  exit 1
fi
BLACKOUT_TUI_CONFIRM=yes
bo_menu_activate
grep -q '^api:disable$' "$events_file"
[ "$(bo_menu_status_value 'user api')" = disabled ]
grep -qx 'Enable' <<<"$(bo_menu_rows | sed -n '1p')"

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
