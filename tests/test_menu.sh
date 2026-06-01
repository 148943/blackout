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
bo_update_cmd() {
  printf 'update:%s\n' "$*" >>"$events_file"
}

output="$(printf '5\n0\n' | bo_menu)"
grep -q 'Blackout control panel' <<<"$output"
grep -qx 'update:check' "$events_file"

: >"$events_file"
output="$(printf '1\n2\n0\n0\n' | bo_menu)"
grep -q 'Users' <<<"$output"
grep -qx 'user:list' "$events_file"

: >"$events_file"
output="$(printf '2\n3\n0\n0\n' | bo_menu)"
grep -q 'Xray' <<<"$output"
grep -qx 'xray:current' "$events_file"
