#!/usr/bin/env bash

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
  printf '%s\n' "$(($(date +%s) + $(bo_duration_seconds "$duration")))"
}
