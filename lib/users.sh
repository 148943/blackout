#!/usr/bin/env bash

if ! declare -F bo_fail >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/common.sh"
fi
if ! declare -F bo_db_user_insert >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/db.sh"
fi
if ! declare -F bo_expiry_epoch >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/time.sh"
fi
if ! declare -F bo_render_template >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/template.sh"
fi
if ! declare -F bo_xray_api >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/xray.sh"
fi

bo_user_validate_username() {
  local username="$1"
  [ -n "$username" ] || bo_fail "username required"
  [ "${#username}" -le 64 ] || bo_fail "username is too long"
  [[ "$username" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || bo_fail "username contains unsafe characters"
}

bo_user_generate_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  else
    bo_fail "missing uuid generator"
  fi
}

bo_user_setting() {
  local key="$1" default="${2:-}" value
  value="$(bo_setting_get "$key" 2>/dev/null || true)"
  printf '%s\n' "${value:-$default}"
}

bo_user_active_inbound() {
  bo_user_setting active_inbound vless-ws
}

bo_xray_add_user() {
  local username="$1" uuid="$2" level="${3:-0}" tag
  tag="$(bo_user_active_inbound)"
  bo_xray_api adu --tag "$tag" --email "$username" --level "$level" --uuid "$uuid"
}

bo_xray_remove_user() {
  local username="$1" tag
  tag="$(bo_user_active_inbound)"
  bo_xray_api rmu --tag "$tag" --email "$username"
}

bo_user_add() {
  local username="$1" password="$2" uuid="$3" expires_at="$4" level="${5:-0}" now email
  bo_user_validate_username "$username"
  [ -n "$password" ] || bo_fail "password required"
  [[ "$expires_at" =~ ^[0-9]+$ ]] || bo_fail "expires_at must be numeric"
  now="$(date +%s)"
  email="$username@example"

  bo_db_user_insert "$username" "$password" "$uuid" "$email" "$level" active "$now" "$expires_at"
  if ! bo_xray_add_user "$username" "$uuid" "$level"; then
    bo_db_user_set_status "$username" locked || true
    return 1
  fi
}

bo_user_add_prompt() {
  local username password duration uuid expires_at
  read -r -p "Username: " username
  read -r -s -p "Password: " password
  printf '\n'
  read -r -p "Duration (12h, 7d, 1m): " duration
  expires_at="$(bo_expiry_epoch "$duration")" || bo_fail "invalid duration: $duration"
  uuid="$(bo_user_generate_uuid)"
  bo_user_add "$username" "$password" "$uuid" "$expires_at"
  printf '%s\n' "$username"
}

bo_user_lock() {
  local username="$1"
  bo_user_validate_username "$username"
  bo_xray_remove_user "$username"
  bo_db_user_set_status "$username" locked
}

bo_user_remove() {
  local username="$1"
  bo_user_validate_username "$username"
  bo_xray_remove_user "$username"
  bo_db_user_delete "$username"
}

bo_user_unlock() {
  local username="$1" row now password uuid email level status created_at expires_at updated_at
  bo_user_validate_username "$username"
  row="$(bo_db_user_get "$username")"
  [ -n "$row" ] || bo_fail "unknown user: $username"
  IFS=$'\t' read -r username password uuid email level status created_at expires_at updated_at <<<"$row"
  now="$(date +%s)"
  if [ "$expires_at" -le "$now" ]; then
    bo_db_user_set_status "$username" expired
    bo_fail "user expired: $username"
  fi
  bo_xray_add_user "$username" "$uuid" "$level"
  bo_db_user_set_status "$username" active
}

bo_user_modify() {
  local username="$1" password duration expires_at
  bo_user_validate_username "$username"
  [ -n "$(bo_db_user_get "$username")" ] || bo_fail "unknown user: $username"
  read -r -s -p "New password: " password
  printf '\n'
  read -r -p "New duration (12h, 7d, 1m): " duration
  expires_at="$(bo_expiry_epoch "$duration")" || bo_fail "invalid duration: $duration"
  bo_db_user_update "$username" "$password" "$expires_at"
}

bo_user_list() {
  bo_db_users_list
}

bo_user_online() {
  local username
  while IFS= read -r username; do
    [ -n "$username" ] || continue
    printf '%s\t' "$username"
    bo_xray_user_stats "$username" || return 1
  done < <(bo_db_active_usernames)
}

bo_user_share_template() {
  local profile template
  profile="$(bo_user_setting profile vless-ws-nginx)"
  template="$BLACKOUT_ETC_DIR/share.template"
  if [ -f "$template" ]; then
    printf '%s\n' "$template"
    return 0
  fi
  template="$BLACKOUT_CONFIG_DIR/$profile/share.template"
  [ -f "$template" ] || bo_fail "missing share template: $profile"
  printf '%s\n' "$template"
}

bo_user_link() {
  local username="$1" row password uuid email level status created_at expires_at updated_at domain ws_path template
  bo_user_validate_username "$username"
  row="$(bo_db_user_get "$username")"
  [ -n "$row" ] || bo_fail "unknown user: $username"
  IFS=$'\t' read -r username password uuid email level status created_at expires_at updated_at <<<"$row"
  [ "$status" = active ] || bo_fail "user is not active: $username"
  domain="$(bo_user_setting domain)"
  [ -n "$domain" ] || bo_fail "domain setting required"
  ws_path="$(bo_user_setting ws_path /vless)"
  template="$(bo_user_share_template)"
  bo_render_template "$template" UUID "$uuid" DOMAIN "$domain" WS_PATH "$ws_path" USERNAME "$username"
  printf '\n'
}

bo_user_expire() {
  local username
  while IFS= read -r username; do
    [ -n "$username" ] || continue
    bo_xray_remove_user "$username"
    bo_db_user_set_status "$username" expired
    printf '%s\n' "$username"
  done < <(bo_db_expired_active_usernames)
}

bo_user_cmd() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    add) bo_user_add_prompt ;;
    remove) bo_user_remove "${1:?username required}" ;;
    modify) bo_user_modify "${1:?username required}" ;;
    lock) bo_user_lock "${1:?username required}" ;;
    unlock) bo_user_unlock "${1:?username required}" ;;
    list) bo_user_list ;;
    online) bo_user_online ;;
    link) bo_user_link "${1:?username required}" ;;
    expire) bo_user_expire ;;
    *) bo_fail "unknown user command: ${cmd:-}" ;;
  esac
}
