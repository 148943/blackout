#!/usr/bin/env bash

bo_menu_load() {
  local function_name="$1" file_name="$2"
  if ! declare -F "$function_name" >/dev/null 2>&1; then
    # shellcheck disable=SC1090
    . "$BLACKOUT_LIB_DIR/$file_name"
  fi
}

bo_menu_read() {
  local prompt="$1" __var="$2" value
  if ! read -r -p "$prompt" value; then
    return 1
  fi
  printf -v "$__var" '%s' "$value"
}

bo_menu_users() {
  local choice username
  bo_menu_load bo_user_cmd users.sh
  while true; do
    bo_log "Users"
    printf '1) Add\n2) List\n3) Online\n4) Link\n5) Modify\n6) Lock\n7) Unlock\n8) Remove\n0) Back\n'
    bo_menu_read 'users> ' choice || return 0
    case "$choice" in
      1) bo_user_cmd add ;;
      2) bo_user_cmd list ;;
      3) bo_user_cmd online ;;
      4) bo_menu_read 'Username: ' username || return 0; bo_user_cmd link "$username" ;;
      5) bo_menu_read 'Username: ' username || return 0; bo_user_cmd modify "$username" ;;
      6) bo_menu_read 'Username: ' username || return 0; bo_user_cmd lock "$username" ;;
      7) bo_menu_read 'Username: ' username || return 0; bo_user_cmd unlock "$username" ;;
      8) bo_menu_read 'Username: ' username || return 0; bo_user_cmd remove "$username" ;;
      0) return 0 ;;
      *) bo_warn "invalid menu choice: $choice" ;;
    esac
  done
}

bo_menu_xray() {
  local choice version
  bo_menu_load bo_xray_cmd xray.sh
  while true; do
    bo_log "Xray"
    printf '1) Install latest\n2) Update latest\n3) Current version\n4) Change version\n0) Back\n'
    bo_menu_read 'xray> ' choice || return 0
    case "$choice" in
      1) bo_xray_cmd install latest ;;
      2) bo_xray_cmd update ;;
      3) bo_xray_cmd current ;;
      4) bo_menu_read 'Version: ' version || return 0; bo_xray_cmd version "$version" ;;
      0) return 0 ;;
      *) bo_warn "invalid menu choice: $choice" ;;
    esac
  done
}

bo_menu_certs() {
  local choice domain email
  bo_menu_load bo_cert_cmd certs.sh
  while true; do
    bo_log "Certificates"
    printf '1) Status\n2) Issue\n3) Renew\n4) Change domain\n0) Back\n'
    bo_menu_read 'certs> ' choice || return 0
    case "$choice" in
      1) bo_cert_cmd status ;;
      2) bo_menu_read 'ACME email: ' email || return 0; bo_menu_read 'Domain: ' domain || return 0; bo_cert_cmd issue "$email" "$domain" ;;
      3) bo_cert_cmd renew ;;
      4) bo_menu_read 'New domain: ' domain || return 0; bo_cert_cmd change-domain "$domain" ;;
      0) return 0 ;;
      *) bo_warn "invalid menu choice: $choice" ;;
    esac
  done
}

bo_menu_config() {
  local choice profile
  bo_menu_load bo_config_cmd configs.sh
  while true; do
    bo_log "Config"
    printf '1) Current\n2) List\n3) Switch\n4) Reload current\n0) Back\n'
    bo_menu_read 'config> ' choice || return 0
    case "$choice" in
      1) bo_config_cmd current ;;
      2) bo_config_cmd list ;;
      3) bo_menu_read 'Profile: ' profile || return 0; bo_config_cmd switch "$profile" ;;
      4) bo_config_cmd reload ;;
      0) return 0 ;;
      *) bo_warn "invalid menu choice: $choice" ;;
    esac
  done
}

bo_menu_api() {
  local choice
  bo_menu_load bo_api_control_cmd api.sh
  while true; do
    bo_log "API"
    printf '1) Enable\n2) Disable\n3) Status\n4) New token\n0) Back\n'
    bo_menu_read 'api> ' choice || return 0
    case "$choice" in
      1) bo_api_control_cmd enable ;;
      2) bo_api_control_cmd disable ;;
      3) bo_api_control_cmd status ;;
      4) bo_api_control_cmd token ;;
      0) return 0 ;;
      *) bo_warn "invalid menu choice: $choice" ;;
    esac
  done
}

bo_menu() {
  local choice
  while true; do
    bo_log "Blackout control panel"
    printf '1) Status\n2) Users\n3) Xray\n4) Certificates\n5) Config\n6) API\n7) Update check\n0) Exit\n'
    bo_menu_read 'blackout> ' choice || return 0
    case "$choice" in
      1) bo_menu_load bo_status_cmd status.sh; bo_status_cmd ;;
      2) bo_menu_users ;;
      3) bo_menu_xray ;;
      4) bo_menu_certs ;;
      5) bo_menu_config ;;
      6) bo_menu_api ;;
      7) bo_menu_load bo_update_cmd update.sh; bo_update_cmd check ;;
      0) return 0 ;;
      *) bo_warn "invalid menu choice: $choice" ;;
    esac
  done
}
