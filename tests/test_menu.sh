#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLACKOUT_LIB_DIR="$ROOT_DIR/lib"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
events_file="$tmp/events"

. "$ROOT_DIR/lib/menu.sh"

bo_log() {
  printf '[BLACKOUT] :: %s\n' "$*"
}
bo_status_cmd() {
  printf 'status:%s\n' "${*:-check}" >>"$events_file"
}
bo_user_cmd() {
  printf 'user:%s\n' "$*" >>"$events_file"
}
bo_xray_cmd() {
  printf 'xray:%s\n' "$*" >>"$events_file"
}
bo_cert_cmd() {
  printf 'cert:%s\n' "$*" >>"$events_file"
}
bo_config_cmd() {
  printf 'config:%s\n' "$*" >>"$events_file"
}
bo_api_control_cmd() {
  printf 'api:%s\n' "$*" >>"$events_file"
}
bo_update_cmd() {
  printf 'update:%s\n' "$*" >>"$events_file"
}

output="$(printf '7\n0\n' | bo_menu)"
grep -q 'Blackout control panel' <<<"$output"
grep -qx 'update:check' "$events_file"

: >"$events_file"
output="$(printf '1\n0\n' | bo_menu)"
grep -qx 'status:check' "$events_file"

: >"$events_file"
output="$(printf '2\n2\n0\n0\n' | bo_menu)"
grep -q 'Users' <<<"$output"
grep -qx 'user:list' "$events_file"

: >"$events_file"
output="$(printf '3\n3\n0\n0\n' | bo_menu)"
grep -q 'Xray' <<<"$output"
grep -qx 'xray:current' "$events_file"

: >"$events_file"
output="$(printf '5\n4\n0\n0\n' | bo_menu)"
grep -q 'Config' <<<"$output"
grep -qx 'config:reload' "$events_file"

: >"$events_file"
output="$(printf '6\n3\n0\n0\n' | bo_menu)"
grep -q 'API' <<<"$output"
grep -qx 'api:status' "$events_file"
