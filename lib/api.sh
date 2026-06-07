#!/usr/bin/env bash

if ! declare -F bo_fail >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/common.sh"
fi
if ! declare -F bo_db_user_get >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/db.sh"
fi
if ! declare -F bo_user_add >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/users.sh"
fi

BO_API_INVALID=10
BO_API_NOT_FOUND=11
BO_API_CONFLICT=12
BO_API_BACKEND=20

bo_api_generate_token() {
  python3 -c 'import secrets; print(secrets.token_urlsafe(32))'
}

bo_api_env_quote() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\$/\\$/g; s/`/\\`/g'
}

bo_api_systemd_quote() {
  printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/%/%%/g; s/\$/$$/g')"
}

bo_api_systemd_path_quote() {
  printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/%/%%/g')"
}

bo_api_systemd_path() {
  printf '%s' "$1" | sed 's/\\/\\x5c/g; s/ /\\x20/g; s/	/\\x09/g; s/%/%%/g; s/\$/\\x24/g'
}

bo_api_install_service() {
  local service_path="${1:?service path required}" api_script="${2:?api script required}" env_file="${3:?env file required}" state_dir="${4:-${BLACKOUT_STATE_DIR:-/var/lib/blackout}}" etc_dir="${5:-${BLACKOUT_ETC_DIR:-/etc/blackout}}" db_path="${6:-${BLACKOUT_DB:-$state_dir/blackout.db}}" db_dir
  db_dir="$(dirname "$db_path")"
  mkdir -p "$(dirname "$service_path")"
  cat >"$service_path" <<EOF_SERVICE
[Unit]
Description=Blackout User API
Wants=network-online.target
After=network-online.target xray.service
Requires=xray.service

[Service]
Type=simple
User=root
Group=root
EnvironmentFile=$(bo_api_systemd_path "$env_file")
ExecStart=/usr/bin/python3 $(bo_api_systemd_quote "$api_script")
Restart=on-failure
RestartSec=3
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true
ReadWritePaths=$(bo_api_systemd_path_quote "$state_dir") $(bo_api_systemd_path_quote "$etc_dir") $(bo_api_systemd_path_quote "$db_dir") /tmp /dev/shm

[Install]
WantedBy=multi-user.target
EOF_SERVICE
  chmod 0644 "$service_path"
}

bo_api_json_string() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "${1:-}"
}

bo_api_error() {
  local status="$1" code="$2" message="$3"
  printf '{"ok":false,"error":{"code":%s,"message":%s}}\n' \
    "$(bo_api_json_string "$code")" \
    "$(bo_api_json_string "$message")"
  return "$status"
}

bo_api_success_raw() {
  printf '{"ok":true,"data":%s}\n' "$1"
}

bo_api_need_arg() {
  local name="$1" value="${2:-}"
  [ -n "$value" ] || bo_api_error "$BO_API_INVALID" invalid_request "$name required"
}

bo_api_need_no_extra() {
  local extra="${1:-}"
  [ -z "$extra" ] || bo_api_error "$BO_API_INVALID" invalid_request "too many arguments"
}

bo_api_user_exists() {
  [ -n "$(bo_db_user_get "$1")" ]
}

bo_api_user_row_or_404() {
  local row
  row="$(bo_db_user_get "$1")" || return "$BO_API_BACKEND"
  if [ -z "$row" ]; then
    return "$BO_API_NOT_FOUND"
  fi
  printf '%s\n' "$row"
}

bo_api_user_json_from_row() {
  local row="$1" username uuid email level status created_at expires_at updated_at
  IFS=$'\t' read -r username uuid email level status created_at expires_at updated_at <<<"$row"
  printf '{"username":%s,"uuid":%s,"level":%s,"status":%s,"created_at":%s,"expires_at":%s,"updated_at":%s}' \
    "$(bo_api_json_string "$username")" \
    "$(bo_api_json_string "$uuid")" \
    "$level" \
    "$(bo_api_json_string "$status")" \
    "$created_at" \
    "$expires_at" \
    "$updated_at"
}

bo_api_user_json_from_list_row() {
  local row="$1" username uuid level status created_at expires_at updated_at
  IFS=$'\t' read -r username uuid level status created_at expires_at updated_at <<<"$row"
  printf '{"username":%s,"uuid":%s,"level":%s,"status":%s,"created_at":%s,"expires_at":%s,"updated_at":%s}' \
    "$(bo_api_json_string "$username")" \
    "$(bo_api_json_string "$uuid")" \
    "$level" \
    "$(bo_api_json_string "$status")" \
    "$created_at" \
    "$expires_at" \
    "$updated_at"
}

bo_api_user_success() {
  local row status
  row="$(bo_api_user_row_or_404 "$1")"
  status=$?
  if [ "$status" -ne 0 ]; then
    case "$status" in
      "$BO_API_NOT_FOUND") bo_api_error "$BO_API_NOT_FOUND" not_found "user not found" ;;
      *) bo_api_error "$BO_API_BACKEND" backend_error "failed to read user" ;;
    esac
    return "$?"
  fi
  bo_api_success_raw "$(bo_api_user_json_from_row "$row")"
}

bo_api_duration_epoch() {
  local duration="$1" expires_at now
  BO_API_DURATION_EPOCH=
  if [ -z "$duration" ]; then
    bo_api_error "$BO_API_INVALID" invalid_request "duration required"
    return "$?"
  fi
  if ! expires_at="$(bo_expiry_epoch "$duration" 2>/dev/null)"; then
    bo_api_error "$BO_API_INVALID" invalid_request "invalid duration"
    return "$?"
  fi
  now="$(date +%s)" || return "$BO_API_BACKEND"
  if [ "$expires_at" -le "$now" ]; then
    bo_api_error "$BO_API_INVALID" invalid_request "duration must be positive"
    return "$?"
  fi
  BO_API_DURATION_EPOCH="$expires_at"
}

bo_api_list() {
  local rows row first=1
  if ! rows="$(bo_db_users_rows)"; then
    bo_api_error "$BO_API_BACKEND" backend_error "failed to list users"
    return "$?"
  fi
  printf '{"ok":true,"data":['
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    if [ "$first" = 1 ]; then
      first=0
    else
      printf ','
    fi
    bo_api_user_json_from_list_row "$row"
  done <<<"$rows"
  printf ']}\n'
}

bo_api_create() {
  local username="${1:-}" duration="${2:-}" extra="${3:-}" uuid expires_at
  bo_api_need_arg username "$username" || return "$?"
  bo_api_need_arg duration "$duration" || return "$?"
  bo_api_need_no_extra "$extra" || return "$?"
  if ! bo_user_validate_username "$username" >/dev/null 2>&1; then
    bo_api_error "$BO_API_INVALID" invalid_request "invalid username"
    return "$?"
  fi
  if bo_api_user_exists "$username"; then
    bo_api_error "$BO_API_CONFLICT" conflict "user already exists"
    return "$?"
  fi
  bo_api_duration_epoch "$duration" || return "$?"
  expires_at="$BO_API_DURATION_EPOCH"
  uuid="$(bo_user_generate_uuid)" || {
    bo_api_error "$BO_API_BACKEND" backend_error "failed to generate uuid"
    return "$?"
  }
  if ! bo_user_add "$username" "$uuid" "$expires_at" >/dev/null 2>&1; then
    bo_api_error "$BO_API_BACKEND" backend_error "failed to create user"
    return "$?"
  fi
  bo_api_user_success "$username"
}

bo_api_modify() {
  local username="${1:-}" duration="${2:-}" extra="${3:-}"
  bo_api_need_arg username "$username" || return "$?"
  bo_api_need_arg duration "$duration" || return "$?"
  bo_api_need_no_extra "$extra" || return "$?"
  bo_api_user_row_or_404 "$username" >/dev/null || {
    case "$?" in
      "$BO_API_NOT_FOUND") bo_api_error "$BO_API_NOT_FOUND" not_found "user not found" ;;
      *) bo_api_error "$BO_API_BACKEND" backend_error "failed to read user" ;;
    esac
    return "$?"
  }
  bo_api_duration_epoch "$duration" || return "$?"
  if ! bo_user_modify_duration "$username" "$duration" >/dev/null 2>&1; then
    bo_api_error "$BO_API_BACKEND" backend_error "failed to modify user"
    return "$?"
  fi
  bo_api_user_success "$username"
}

bo_api_remove() {
  local username="${1:-}" extra="${2:-}"
  bo_api_need_arg username "$username" || return "$?"
  bo_api_need_no_extra "$extra" || return "$?"
  bo_api_user_row_or_404 "$username" >/dev/null || {
    case "$?" in
      "$BO_API_NOT_FOUND") bo_api_error "$BO_API_NOT_FOUND" not_found "user not found" ;;
      *) bo_api_error "$BO_API_BACKEND" backend_error "failed to read user" ;;
    esac
    return "$?"
  }
  if ! bo_user_remove "$username" >/dev/null 2>&1; then
    bo_api_error "$BO_API_BACKEND" backend_error "failed to remove user"
    return "$?"
  fi
  bo_api_success_raw "{\"username\":$(bo_api_json_string "$username")}"
}

bo_api_lock() {
  local username="${1:-}" extra="${2:-}"
  bo_api_need_arg username "$username" || return "$?"
  bo_api_need_no_extra "$extra" || return "$?"
  bo_api_user_row_or_404 "$username" >/dev/null || {
    case "$?" in
      "$BO_API_NOT_FOUND") bo_api_error "$BO_API_NOT_FOUND" not_found "user not found" ;;
      *) bo_api_error "$BO_API_BACKEND" backend_error "failed to read user" ;;
    esac
    return "$?"
  }
  if ! bo_user_lock "$username" >/dev/null 2>&1; then
    bo_api_error "$BO_API_BACKEND" backend_error "failed to lock user"
    return "$?"
  fi
  bo_api_user_success "$username"
}

bo_api_unlock() {
  local username="${1:-}" extra="${2:-}"
  bo_api_need_arg username "$username" || return "$?"
  bo_api_need_no_extra "$extra" || return "$?"
  bo_api_user_row_or_404 "$username" >/dev/null || {
    case "$?" in
      "$BO_API_NOT_FOUND") bo_api_error "$BO_API_NOT_FOUND" not_found "user not found" ;;
      *) bo_api_error "$BO_API_BACKEND" backend_error "failed to read user" ;;
    esac
    return "$?"
  }
  if ! bo_user_unlock "$username" >/dev/null 2>&1; then
    bo_api_error "$BO_API_BACKEND" backend_error "failed to unlock user"
    return "$?"
  fi
  bo_api_user_success "$username"
}

bo_api_links() {
  local username="${1:-}" extra="${2:-}" rows row name link first=1
  bo_api_need_arg username "$username" || return "$?"
  bo_api_need_no_extra "$extra" || return "$?"
  bo_api_user_row_or_404 "$username" >/dev/null || {
    case "$?" in
      "$BO_API_NOT_FOUND") bo_api_error "$BO_API_NOT_FOUND" not_found "user not found" ;;
      *) bo_api_error "$BO_API_BACKEND" backend_error "failed to read user" ;;
    esac
    return "$?"
  }
  if ! rows="$(bo_user_link_rows "$username" 2>/dev/null)"; then
    bo_api_error "$BO_API_BACKEND" backend_error "failed to render links"
    return "$?"
  fi
  printf '{"ok":true,"data":['
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    name="${row%%$'\t'*}"
    link="${row#*$'\t'}"
    if [ "$first" = 1 ]; then
      first=0
    else
      printf ','
    fi
    printf '{"name":%s,"link":%s}' "$(bo_api_json_string "$name")" "$(bo_api_json_string "$link")"
  done <<<"$rows"
  printf ']}\n'
}

bo_api_online() {
  local sample="${1:-5}" extra="${2:-}" rows row username delta total first=1
  bo_api_need_no_extra "$extra" || return "$?"
  case "$sample" in
    ''|*[!0-9]*)
      bo_api_error "$BO_API_INVALID" invalid_request "sample seconds must be numeric"
      return "$?"
      ;;
  esac
  if ! rows="$(bo_user_online_rows "$sample" 2>/dev/null)"; then
    bo_api_error "$BO_API_BACKEND" backend_error "failed to sample online users"
    return "$?"
  fi
  printf '{"ok":true,"data":['
  while IFS=$'\t' read -r username delta total; do
    [ -n "$username" ] || continue
    if [ "$first" = 1 ]; then
      first=0
    else
      printf ','
    fi
    printf '{"username":%s,"delta_bytes":%s,"total_bytes":%s}' \
      "$(bo_api_json_string "$username")" "$delta" "$total"
  done <<<"$rows"
  printf ']}\n'
}

bo_api_cmd() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    list) bo_api_need_no_extra "${1:-}" && bo_api_list ;;
    create) bo_api_create "$@" ;;
    modify) bo_api_modify "$@" ;;
    remove) bo_api_remove "$@" ;;
    lock) bo_api_lock "$@" ;;
    unlock) bo_api_unlock "$@" ;;
    links) bo_api_links "$@" ;;
    online) bo_api_online "$@" ;;
    *) bo_api_error "$BO_API_INVALID" invalid_request "unknown api command" ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set +e
  bo_api_cmd "$@"
  exit "$?"
fi
