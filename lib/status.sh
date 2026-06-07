#!/usr/bin/env bash

if ! declare -F bo_fail >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/common.sh"
fi
if ! declare -F bo_setting_get >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/db.sh"
fi
if ! declare -F bo_xray_api >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/xray.sh"
fi

bo_status_line() {
  printf '%s: %s\n' "$1" "$2"
}

bo_status_systemd_active() {
  systemctl is-active --quiet "$1"
}

bo_status_database() {
  local count
  [ -f "$BLACKOUT_DB" ] || return 1
  count="$(sqlite3 "$BLACKOUT_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('users','settings');" 2>/dev/null)" || return 1
  [ "$count" = 2 ]
}

bo_status_config_profile() {
  local profile profile_dir
  profile="$(bo_setting_get profile 2>/dev/null || true)"
  profile="${profile:-${BLACKOUT_DEFAULT_PROFILE:-default}}"
  profile_dir="${BLACKOUT_CONFIG_DIR:-/opt/blackout/configs}/$profile"
  [ -d "$profile_dir" ] || return 1
  [ -f "$profile_dir/xray.conf" ] || return 1
  [ -f "$profile_dir/nginx.conf" ] || return 1
  [ -f "$profile_dir/share.template" ] || return 1
}

bo_status_xray_api() {
  bo_xray_api statsquery --pattern '' --reset=false >/dev/null
}

bo_status_nginx_config() {
  nginx -t >/dev/null 2>&1
}

bo_status_user_api() {
  local service_path="${BLACKOUT_API_SERVICE_PATH:-/etc/systemd/system/blackout-api.service}" service_name env_file="${BLACKOUT_ENV:-${BLACKOUT_ETC_DIR:-/etc/blackout}/blackout.env}" host port token
  service_name="$(basename "$service_path")"
  service_name="${BLACKOUT_API_SERVICE_NAME:-${service_name%.service}}"
  if ! systemctl is-enabled --quiet "$service_name" >/dev/null 2>&1; then
    bo_status_line "user api" "disabled"
    return 0
  fi
  if ! bo_status_systemd_active "$service_name"; then
    bo_status_line "user api" "fail"
    return 1
  fi
  if ! declare -F bo_api_env_get >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/api.sh"
  fi
  host="${BLACKOUT_API_HOST:-$(bo_api_env_get "$env_file" BLACKOUT_API_HOST)}"
  port="${BLACKOUT_API_PORT:-$(bo_api_env_get "$env_file" BLACKOUT_API_PORT)}"
  token="${BLACKOUT_API_TOKEN:-$(bo_api_env_get "$env_file" BLACKOUT_API_TOKEN)}"
  host="${host:-127.0.0.1}"
  port="${port:-8787}"
  [ -n "$token" ] || {
    bo_status_line "user api" "fail"
    return 1
  }
  if curl -fsS -H "Authorization: Bearer $token" "http://$host:$port/blackout-api/v1/users" >/dev/null; then
    bo_status_line "user api" "ok"
    return 0
  fi
  bo_status_line "user api" "fail"
  return 1
}

bo_status_check() {
  local label="$1" failed_var="$2"
  shift 2
  if "$@"; then
    bo_status_line "$label" "ok"
  else
    bo_status_line "$label" "fail"
    printf -v "$failed_var" 1
  fi
}

bo_status_cmd() {
  local failed=0
  bo_status_check "xray service" failed bo_status_systemd_active xray
  bo_status_check "xray api" failed bo_status_xray_api
  bo_status_check "nginx service" failed bo_status_systemd_active nginx
  bo_status_check "nginx config" failed bo_status_nginx_config
  bo_status_check "database" failed bo_status_database
  bo_status_check "config profile" failed bo_status_config_profile
  bo_status_user_api || failed=1
  if [ "$failed" = 0 ]; then
    bo_status_line "overall" "usable"
    return 0
  fi
  bo_status_line "overall" "failed"
  return 1
}
