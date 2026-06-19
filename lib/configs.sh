#!/usr/bin/env bash

if ! declare -F bo_fail >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/common.sh"
fi
if ! declare -F bo_setting_get >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/db.sh"
fi
if ! declare -F bo_render_template >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/template.sh"
fi
if ! declare -F bo_nginx_install_site >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/nginx.sh"
fi
if ! declare -F bo_xray_api_port >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/xray.sh"
fi

BLACKOUT_DEFAULT_PROFILE="${BLACKOUT_DEFAULT_PROFILE:-default}"
BLACKOUT_XRAY_CONFIG="${BLACKOUT_XRAY_CONFIG:-/etc/xray/config.json}"

bo_config_setting() {
  local key="$1" default="${2:-}" value
  value="$(bo_setting_get "$key" 2>/dev/null || true)"
  printf '%s\n' "${value:-$default}"
}

bo_config_current() {
  bo_config_setting profile "$BLACKOUT_DEFAULT_PROFILE"
}

bo_config_list() {
  [ -d "$BLACKOUT_CONFIG_DIR" ] || return 0
  find "$BLACKOUT_CONFIG_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}

bo_config_profile_dir() {
  local profile="$1"
  printf '%s/%s\n' "$BLACKOUT_CONFIG_DIR" "$profile"
}

bo_config_validate_inputs() {
  local domain="$1" xray_api_port="$2"
  [ -n "$domain" ] || bo_fail "domain setting required"
  [ "${#domain}" -le 253 ] || bo_fail "domain is too long"
  [[ "$domain" =~ ^(\*\.)?[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]] || bo_fail "domain contains unsafe characters"
  case "$xray_api_port" in
    ''|*[!0-9]*) bo_fail "xray_api_port must be numeric" ;;
  esac
}

bo_config_template_domain() {
  local domain="$1"
  if [[ "$domain" == \*.* ]]; then
    printf '%s\n' "${domain#*.}"
  else
    printf '%s\n' "$domain"
  fi
}

bo_config_api_nginx_block() {
  cat <<'EOF'
    location /blackout-api/ {
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_pass http://127.0.0.1:8787;
    }
EOF
}

bo_config_switch() {
  local profile="${1:?profile required}" profile_dir domain template_domain xray_api_port stage nginx_snapshot ssl_cert ssl_key api_nginx_block
  profile_dir="$(bo_config_profile_dir "$profile")"
  [ -d "$profile_dir" ] || bo_fail "unknown profile: $profile"
  [ -f "$profile_dir/xray.conf" ] || bo_fail "missing xray template: $profile"
  [ -f "$profile_dir/nginx.conf" ] || bo_fail "missing nginx template: $profile"
  [ -f "$profile_dir/share.template" ] || bo_fail "missing share template: $profile"

  bo_need_cmd jq
  domain="$(bo_config_setting domain "${DOMAIN:-}")"
  xray_api_port="$(bo_xray_api_port)" || return 1
  bo_config_validate_inputs "$domain" "$xray_api_port"
  template_domain="$(bo_config_template_domain "$domain")"
  ssl_cert="${BLACKOUT_SSL_FULLCHAIN:-${BLACKOUT_SSL_DIR:-${BLACKOUT_ETC_DIR:-/etc/blackout}/ssl}/fullchain.pem}"
  ssl_key="${BLACKOUT_SSL_PRIVKEY:-${BLACKOUT_SSL_DIR:-${BLACKOUT_ETC_DIR:-/etc/blackout}/ssl}/privkey.pem}"
  api_nginx_block="$(bo_config_api_nginx_block)"

  stage="$(mktemp -d)"

  bo_render_template "$profile_dir/xray.conf" \
    DOMAIN "$template_domain" XRAY_API_PORT "$xray_api_port" SSL_CERT "$ssl_cert" SSL_KEY "$ssl_key" API_NGINX_BLOCK "$api_nginx_block" \
    >"$stage/xray.conf"
  bo_render_template "$profile_dir/nginx.conf" \
    DOMAIN "$template_domain" XRAY_API_PORT "$xray_api_port" SSL_CERT "$ssl_cert" SSL_KEY "$ssl_key" API_NGINX_BLOCK "$api_nginx_block" \
    >"$stage/nginx.conf"
  cp "$profile_dir/share.template" "$stage/share.template"

  if ! jq -e . "$stage/xray.conf" >/dev/null; then
    rm -rf "$stage"
    return 1
  fi

  nginx_snapshot="$stage/nginx-snapshot"
  bo_nginx_snapshot_site "$nginx_snapshot"
  bo_nginx_install_site "$stage/nginx.conf"
  if ! bo_nginx_test; then
    bo_nginx_restore_site "$nginx_snapshot"
    rm -rf "$stage"
    return 1
  fi

  mkdir -p "$(dirname "$BLACKOUT_XRAY_CONFIG")" "$BLACKOUT_ETC_DIR"
  install -m 0644 "$stage/xray.conf" "$BLACKOUT_XRAY_CONFIG"
  install -m 0644 "$stage/share.template" "$BLACKOUT_ETC_DIR/share.template"
  bo_setting_set profile "$profile"
  bo_setting_set xray_api_port "$xray_api_port"

  systemctl restart xray
  if ! declare -F bo_user_sync_active_to_xray >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/users.sh"
  fi
  if ! bo_user_sync_active_to_xray; then
    rm -rf "$stage"
    return 1
  fi
  bo_nginx_reload
  rm -rf "$stage"
}

bo_config_ws_path() {
  bo_fail "ws_path is profile-managed; edit the active config profile and run blackout config reload"
}

bo_config_reload() {
  bo_config_switch "$(bo_config_current)"
}

bo_config_cmd() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    list) bo_config_list ;;
    current) bo_config_current ;;
    switch) bo_config_switch "${1:?profile required}" ;;
    ws-path) bo_config_ws_path "${1:?ws_path required}" ;;
    reload) bo_config_reload ;;
    *) bo_fail "unknown config command: ${cmd:-}" ;;
  esac
}
