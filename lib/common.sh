#!/usr/bin/env bash

BLACKOUT_VERSION="${BLACKOUT_VERSION:-dev}"
BLACKOUT_LIB_DIR="${BLACKOUT_LIB_DIR:-/opt/blackout/lib}"
BLACKOUT_CONFIG_DIR="${BLACKOUT_CONFIG_DIR:-/opt/blackout/configs}"
BLACKOUT_ETC_DIR="${BLACKOUT_ETC_DIR:-/etc/blackout}"
BLACKOUT_STATE_DIR="${BLACKOUT_STATE_DIR:-/var/lib/blackout}"
BLACKOUT_DB="${BLACKOUT_DB:-$BLACKOUT_STATE_DIR/blackout.db}"
BLACKOUT_ENV="${BLACKOUT_ENV:-$BLACKOUT_ETC_DIR/blackout.env}"

if [ -f "$BLACKOUT_ENV" ]; then
  # shellcheck disable=SC1090
  . "$BLACKOUT_ENV"
fi

bo_color() {
  case "${NO_COLOR:-0}:$1" in
    1:*) printf '' ;;
    *:bold) printf '\033[1m' ;;
    *:dim) printf '\033[2m' ;;
    *:green) printf '\033[32m' ;;
    *:cyan) printf '\033[36m' ;;
    *:red) printf '\033[31m' ;;
    *:yellow) printf '\033[33m' ;;
    *:blue) printf '\033[34m' ;;
    *:magenta) printf '\033[35m' ;;
    *:white) printf '\033[37m' ;;
    *:gray) printf '\033[90m' ;;
    *:selected) printf '\033[30;46m' ;;
    *:reset) printf '\033[0m' ;;
  esac
}

bo_log() { printf '%s[BLACKOUT]%s :: %s\n' "$(bo_color green)" "$(bo_color reset)" "$*"; }
bo_trace() { printf '%s[TRACE]%s    :: %s\n' "$(bo_color cyan)" "$(bo_color reset)" "$*"; }
bo_warn() { printf '%s[WARN]%s     :: %s\n' "$(bo_color yellow)" "$(bo_color reset)" "$*" >&2; }
bo_fail() { printf '%s[FAIL]%s     :: %s\n' "$(bo_color red)" "$(bo_color reset)" "$*" >&2; exit 1; }

bo_need_root() {
  [ "$(id -u)" -eq 0 ] || bo_fail "root required"
}

bo_need_cmd() {
  command -v "$1" >/dev/null 2>&1 || bo_fail "missing command: $1"
}

bo_backup_file() {
  local path="$1"
  [ -e "$path" ] || return 0
  local backup_dir="${BLACKOUT_BACKUP_DIR:-/var/backups/blackout}/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir"
  cp -a "$path" "$backup_dir/"
  bo_trace "backup: $path -> $backup_dir/"
}
