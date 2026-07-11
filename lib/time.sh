#!/usr/bin/env bash

BLACKOUT_NEVER_EXPIRES_AT="${BLACKOUT_NEVER_EXPIRES_AT:-4102444800}"

bo_duration_seconds() {
  local value="$1" number unit
  [[ "$value" =~ ^([0-9]+)([hdm])$ ]] || return 1
  number="${BASH_REMATCH[1]}"
  unit="${BASH_REMATCH[2]}"
  case "$unit" in
    h) printf '%s\n' $((number * 3600)) ;;
    d) printf '%s\n' $((number * 86400)) ;;
    m) printf '%s\n' $((number * 2592000)) ;;
  esac
}

bo_expiry_epoch() {
  local duration="$1"
  if [ "$duration" = never ]; then
    printf '%s\n' "$BLACKOUT_NEVER_EXPIRES_AT"
    return
  fi
  printf '%s\n' "$(($(date +%s) + $(bo_duration_seconds "$duration")))"
}

bo_expiry_text() {
  local epoch="$1"
  if [ "$epoch" = "$BLACKOUT_NEVER_EXPIRES_AT" ]; then
    printf 'never\n'
  else
    LC_TIME=C date -u -d "@$epoch" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || printf '%s\n' "$epoch"
  fi
}

bo_expiry_short_text() {
  local epoch="$1"
  if [ "$epoch" = "$BLACKOUT_NEVER_EXPIRES_AT" ]; then
    printf 'never\n'
  else
    LC_TIME=C date -u -d "@$epoch" '+%-d %b %Y' 2>/dev/null || printf '%s\n' "$epoch"
  fi
}
