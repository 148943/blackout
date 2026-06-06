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
  if [ -z "$username" ]; then
    printf 'username required\n' >&2
    return 1
  fi
  if [ "${#username}" -gt 64 ]; then
    printf 'username is too long\n' >&2
    return 1
  fi
  if ! [[ "$username" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    printf 'username contains unsafe characters\n' >&2
    return 1
  fi
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
  bo_user_setting active_inbound vless
}

bo_xray_add_user() {
  local username="$1" uuid="$2" level="${3:-0}" tag tmp
  [[ "$level" =~ ^[0-9]+$ ]] || return 1
  tag="$(bo_user_active_inbound)" || return 1
  tmp="$(mktemp)" || return 1
  {
    printf '{\n'
    printf '  "inbounds": [\n'
    printf '    {\n'
    printf '      "tag": "%s",\n' "$tag"
    printf '      "listen": "127.0.0.1",\n'
    printf '      "port": 1,\n'
    printf '      "protocol": "vless",\n'
    printf '      "settings": {\n'
    printf '        "clients": [\n'
    printf '          {"id": "%s", "email": "%s", "level": %s}\n' "$uuid" "$username" "$level"
    printf '        ],\n'
    printf '        "decryption": "none"\n'
    printf '      }\n'
    printf '    }\n'
    printf '  ]\n'
    printf '}\n'
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  bo_xray_api adu "$tmp"
  local status=$?
  rm -f "$tmp"
  return "$status"
}

bo_xray_remove_user() {
  local username="$1" tag
  tag="$(bo_user_active_inbound)" || return 1
  bo_xray_api rmu "-tag=$tag" "$username"
}

bo_user_sync_active_to_xray() {
  local rows username uuid level now
  [ -e "${BLACKOUT_DB:-}" ] || return 0
  now="$(date +%s)" || return 1
  rows="$(bo_db_active_users "$now")" || return 1
  while IFS=$'\t' read -r username uuid level; do
    [ -n "${username:-}" ] || continue
    if ! bo_xray_add_user "$username" "$uuid" "$level"; then
      printf 'failed to replay active user to xray: %s\n' "$username" >&2
      return 1
    fi
  done <<<"$rows"
}

bo_user_add() {
  local username="$1" uuid="$2" expires_at="$3" level="${4:-0}" now email
  bo_user_validate_username "$username" || return 1
  if ! [[ "$expires_at" =~ ^[0-9]+$ ]]; then
    printf 'expires_at must be numeric\n' >&2
    return 1
  fi
  if ! [[ "$level" =~ ^[0-9]+$ ]]; then
    printf 'level must be numeric\n' >&2
    return 1
  fi
  now="$(date +%s)" || return 1
  if [ "$expires_at" -le "$now" ]; then
    printf 'expires_at must be in the future\n' >&2
    return 1
  fi
  email="$username@example"

  bo_db_user_insert "$username" "$uuid" "$email" "$level" active "$now" "$expires_at" || return 1
  if ! bo_xray_add_user "$username" "$uuid" "$level"; then
    bo_db_user_set_status "$username" locked || true
    return 1
  fi
}

bo_user_add_prompt() {
  local username duration uuid expires_at
  read -r -p "Username: " username
  read -r -p "Duration (12h, 7d, 1m): " duration
  if ! expires_at="$(bo_expiry_epoch "$duration")"; then
    printf 'invalid duration: %s\n' "$duration" >&2
    return 1
  fi
  uuid="$(bo_user_generate_uuid)" || return 1
  bo_user_add "$username" "$uuid" "$expires_at" || return 1
  printf '%s\n' "$username"
}

bo_user_lock() {
  local username="$1" row
  bo_user_validate_username "$username" || return 1
  row="$(bo_db_user_get "$username")" || return 1
  if [ -z "$row" ]; then
    printf 'unknown user: %s\n' "$username" >&2
    return 1
  fi
  bo_xray_remove_user "$username" || return 1
  bo_db_user_set_status "$username" locked || return 1
}

bo_user_remove() {
  local username="$1" row
  bo_user_validate_username "$username" || return 1
  row="$(bo_db_user_get "$username")" || return 1
  if [ -z "$row" ]; then
    printf 'unknown user: %s\n' "$username" >&2
    return 1
  fi
  bo_xray_remove_user "$username" || return 1
  bo_db_user_delete "$username" || return 1
}

bo_user_mark_expired_runtime() {
  local username="$1"
  bo_user_validate_username "$username" || return 1
  bo_xray_remove_user "$username" || return 1
  bo_db_user_set_status "$username" expired || return 1
}

bo_user_unlock() {
  local username="$1" row now uuid email level status created_at expires_at updated_at
  bo_user_validate_username "$username" || return 1
  row="$(bo_db_user_get "$username")" || return 1
  if [ -z "$row" ]; then
    printf 'unknown user: %s\n' "$username" >&2
    return 1
  fi
  IFS=$'\t' read -r username uuid email level status created_at expires_at updated_at <<<"$row"
  now="$(date +%s)" || return 1
  if [ "$expires_at" -le "$now" ]; then
    bo_user_mark_expired_runtime "$username" || return 1
    printf 'user expired: %s\n' "$username" >&2
    return 1
  fi
  bo_xray_add_user "$username" "$uuid" "$level" || return 1
  bo_db_user_set_status "$username" active || return 1
}

bo_user_modify_duration() {
  local username="$1" duration="$2" expires_at row
  bo_user_validate_username "$username" || return 1
  row="$(bo_db_user_get "$username")" || return 1
  if [ -z "$row" ]; then
    printf 'unknown user: %s\n' "$username" >&2
    return 1
  fi
  if ! expires_at="$(bo_expiry_epoch "$duration")"; then
    printf 'invalid duration: %s\n' "$duration" >&2
    return 1
  fi
  bo_db_user_update "$username" "$expires_at"
}

bo_user_modify() {
  local username="$1" duration
  read -r -p "New duration (12h, 7d, 1m): " duration
  bo_user_modify_duration "$username" "$duration"
}

bo_user_list() {
  bo_db_users_list || return 1
}

bo_user_format_bytes() {
  local bytes="$1"
  awk -v bytes="$bytes" 'BEGIN {
    split("B KiB MiB GiB TiB", units, " ")
    value = bytes + 0
    unit = 1
    while (value >= 1024 && unit < 5) {
      value = value / 1024
      unit++
    }
    if (unit == 1) {
      printf "%d %s", value, units[unit]
    } else {
      printf "%.1f %s", value, units[unit]
    }
  }'
}

bo_user_stat_value() {
  local stats="$1" username="$2" direction="$3"
  if command -v jq >/dev/null 2>&1 && jq -e . >/dev/null 2>&1 <<<"$stats"; then
    jq -r --arg name "user>>>$username>>>traffic>>>$direction" \
      '[.stat[]? | select(.name == $name) | .value] | first // 0' <<<"$stats"
    return
  fi
  awk -v name="user>>>$username>>>traffic>>>$direction" '
    index($0, name) {
      seen = 1
      for (i = 1; i <= NF; i++) {
        if ($i == "value:") {
          print $(i + 1)
          found = 1
          exit
        }
      }
    }
    seen && match($0, /"value"[[:space:]]*:[[:space:]]*([0-9]+)/, parts) {
      print parts[1]
      found = 1
      exit
    }
    END {
      if (!found) print 0
    }
  ' <<<"$stats"
}

bo_user_online_rows() {
  local sample username usernames before after after_uplink after_downlink delta_uplink delta_downlink delta total
  local -A before_uplink before_downlink
  sample="${1:-5}"
  case "$sample" in
    ''|*[!0-9]*) bo_fail "sample seconds must be numeric" ;;
  esac
  usernames="$(bo_db_active_usernames)" || return 1
  [ -n "$usernames" ] || return 0
  while IFS= read -r username; do
    [ -n "$username" ] || continue
    before="$(bo_xray_user_stats "$username")" || return 1
    before_uplink["$username"]="$(bo_user_stat_value "$before" "$username" uplink)"
    before_downlink["$username"]="$(bo_user_stat_value "$before" "$username" downlink)"
  done <<<"$usernames"
  if [ "$sample" -gt 0 ]; then
    sleep "$sample"
  fi
  while IFS= read -r username; do
    [ -n "$username" ] || continue
    after="$(bo_xray_user_stats "$username")" || return 1
    after_uplink="$(bo_user_stat_value "$after" "$username" uplink)"
    after_downlink="$(bo_user_stat_value "$after" "$username" downlink)"
    delta_uplink=$((after_uplink - before_uplink[$username]))
    delta_downlink=$((after_downlink - before_downlink[$username]))
    [ "$delta_uplink" -ge 0 ] || delta_uplink=0
    [ "$delta_downlink" -ge 0 ] || delta_downlink=0
    delta=$((delta_uplink + delta_downlink))
    [ "$delta" -gt 0 ] || continue
    total=$((after_uplink + after_downlink))
    printf '%s\t%s\t%s\n' "$username" "$delta" "$total"
  done <<<"$usernames"
}

bo_user_online() {
  local username delta total rows
  rows="$(bo_user_online_rows "${1:-5}")" || return 1
  while IFS=$'\t' read -r username delta total; do
    [ -n "$username" ] || continue
    printf '%s  status=online  delta=%s  total=%s\n' \
      "$username" \
      "$(bo_user_format_bytes "$delta")" \
      "$(bo_user_format_bytes "$total")"
  done <<<"$rows"
}

bo_user_share_template() {
  local profile template
  profile="$(bo_user_setting profile default)"
  template="$BLACKOUT_CONFIG_DIR/$profile/share.template"
  if [ -f "$template" ]; then
    printf '%s\n' "$template"
    return 0
  fi
  template="$BLACKOUT_ETC_DIR/share.template"
  if [ ! -f "$template" ]; then
    printf 'missing share template: %s\n' "$profile" >&2
    return 1
  fi
  printf '%s\n' "$template"
}

bo_user_share_domain() {
  local domain="$1"
  if [[ "$domain" == \*.* ]]; then
    printf '%s\n' "${domain#*.}"
  else
    printf '%s\n' "$domain"
  fi
}

bo_user_link_pairs() {
  local rendered="$1" non_empty name link count
  non_empty="$(awk 'NF { print }' <<<"$rendered")"
  count="$(wc -l <<<"$non_empty" | tr -d ' ')"
  if [ "$count" -le 1 ]; then
    printf '\t%s\n' "$non_empty"
    return
  fi
  while IFS= read -r name; do
    IFS= read -r link || link=""
    [ -n "$name" ] || continue
    printf '%s\t%s\n' "$name" "$link"
  done <<<"$non_empty"
}

bo_user_link_rows() {
  local username="$1" row uuid email level status created_at expires_at updated_at domain share_domain ws_path template now rendered
  bo_user_validate_username "$username" || return 1
  row="$(bo_db_user_get "$username")" || return 1
  if [ -z "$row" ]; then
    printf 'unknown user: %s\n' "$username" >&2
    return 1
  fi
  IFS=$'\t' read -r username uuid email level status created_at expires_at updated_at <<<"$row"
  if [ "$status" != active ]; then
    printf 'user is not active: %s\n' "$username" >&2
    return 1
  fi
  now="$(date +%s)" || return 1
  if [ "$expires_at" -le "$now" ]; then
    bo_user_mark_expired_runtime "$username" || return 1
    printf 'user expired: %s\n' "$username" >&2
    return 1
  fi
  domain="$(bo_user_setting domain)" || return 1
  if [ -z "$domain" ]; then
    printf 'domain setting required\n' >&2
    return 1
  fi
  share_domain="$(bo_user_share_domain "$domain")" || return 1
  ws_path="$(bo_user_setting ws_path /vless)" || return 1
  template="$(bo_user_share_template)" || return 1
  rendered="$(bo_render_template "$template" UUID "$uuid" DOMAIN "$share_domain" WS_PATH "$ws_path" USERNAME "$username")" || return 1
  bo_user_link_pairs "$rendered"
}

bo_user_link() {
  local username="$1" row name link rows_file status
  rows_file="$(mktemp)" || return 1
  if bo_user_link_rows "$username" >"$rows_file"; then
    :
  else
    status=$?
    rm -f "$rows_file"
    return "$status"
  fi
  while IFS= read -r row; do
    name="${row%%$'\t'*}"
    link="${row#*$'\t'}"
    if [ -z "$name" ]; then
      printf '%s\n' "$link"
    elif [ -z "$link" ]; then
      printf '%s\n' "$name"
    else
      printf '%s:\n%s\n\n' "$name" "$link"
    fi
  done <"$rows_file"
  rm -f "$rows_file"
}

bo_user_expire() {
  local username usernames
  usernames="$(bo_db_expired_active_usernames)" || return 1
  while IFS= read -r username; do
    [ -n "$username" ] || continue
    bo_user_mark_expired_runtime "$username" || return 1
    printf '%s\n' "$username"
  done <<<"$usernames"
}

bo_user_need_arg() {
  local name="$1" value="${2:-}"
  if [ -z "$value" ]; then
    printf '%s required\n' "$name" >&2
    return 2
  fi
}

bo_user_cmd() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    add) bo_user_add_prompt ;;
    remove) bo_user_need_arg username "${1:-}" && bo_user_remove "$1" ;;
    modify) bo_user_need_arg username "${1:-}" && bo_user_modify "$1" ;;
    lock) bo_user_need_arg username "${1:-}" && bo_user_lock "$1" ;;
    unlock) bo_user_need_arg username "${1:-}" && bo_user_unlock "$1" ;;
    list) bo_user_list ;;
    online) bo_user_online "$@" ;;
    link) bo_user_need_arg username "${1:-}" && bo_user_link "$1" ;;
    expire) bo_user_expire ;;
    *) bo_fail "unknown user command: ${cmd:-}" ;;
  esac
}
