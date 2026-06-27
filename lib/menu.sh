#!/usr/bin/env bash

if ! declare -F bo_tui_enter >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/tui.sh"
fi

BO_MENU_SCREEN=dashboard
BO_MENU_SELECTION=0
BO_MENU_SHOW_HELP=0
BO_MENU_RUNNING=0
BO_MENU_STATUS=""
BO_MENU_RESULT=""
BO_MENU_KEY_TIMEOUT="${BLACKOUT_TUI_KEY_TIMEOUT:-86400}"
BO_MENU_USERS=""
BO_MENU_PROFILES=""
BO_MENU_ONLINE_USERS="${BO_MENU_ONLINE_USERS:-}"
BO_MENU_SELECTED_USER=""
BO_MENU_SELECTED_USER_STATUS=""
BO_MENU_ONLINE_PID=""
BO_MENU_ONLINE_FILE=""

bo_menu_load() {
  local function_name="$1" file_name="$2"
  if ! declare -F "$function_name" >/dev/null 2>&1; then
    # shellcheck disable=SC1090
    . "$BLACKOUT_LIB_DIR/$file_name"
  fi
}

bo_menu_init() {
  BO_MENU_SCREEN=dashboard
  BO_MENU_SELECTION=0
  BO_MENU_SHOW_HELP=0
  BO_MENU_RUNNING=1
  BO_MENU_RESULT=""
  bo_menu_collect_status || true
}

bo_menu_collect_users() {
  bo_menu_load bo_db_users_rows db.sh
  BO_MENU_USERS="$(bo_db_users_rows 2>/dev/null || true)"
}

bo_menu_collect_profiles() {
  local active profile output=""
  bo_menu_load bo_config_list configs.sh
  active="$(bo_config_current 2>/dev/null || printf 'default')"
  while IFS= read -r profile; do
    [ -n "$profile" ] || continue
    if [ "$profile" = "$active" ]; then
      output+="$profile"$'\tactive\n'
    else
      output+="$profile"$'\tinactive\n'
    fi
  done <<<"$(bo_config_list 2>/dev/null || true)"
  BO_MENU_PROFILES="${output%$'\n'}"
}

bo_menu_online_start() {
  [ "$BO_MENU_SCREEN" = users ] || return 0
  [ -z "$BO_MENU_ONLINE_PID" ] || return 0
  declare -F bo_user_online_rows >/dev/null 2>&1 || return 0
  BO_MENU_ONLINE_FILE="$(mktemp)" || return 0
  bo_user_online_rows "${BLACKOUT_TUI_ONLINE_SAMPLE:-2}" >"$BO_MENU_ONLINE_FILE" 2>/dev/null &
  BO_MENU_ONLINE_PID=$!
}

bo_menu_online_poll() {
  [ -n "$BO_MENU_ONLINE_PID" ] || {
    bo_menu_online_start
    return
  }
  if kill -0 "$BO_MENU_ONLINE_PID" 2>/dev/null; then
    return
  fi
  wait "$BO_MENU_ONLINE_PID" 2>/dev/null || true
  BO_MENU_ONLINE_USERS="$(cat "$BO_MENU_ONLINE_FILE" 2>/dev/null || true)"
  rm -f "$BO_MENU_ONLINE_FILE"
  BO_MENU_ONLINE_PID=""
  BO_MENU_ONLINE_FILE=""
  bo_menu_online_start
}

bo_menu_online_stop() {
  if [ -n "$BO_MENU_ONLINE_PID" ]; then
    kill "$BO_MENU_ONLINE_PID" 2>/dev/null || true
    wait "$BO_MENU_ONLINE_PID" 2>/dev/null || true
  fi
  [ -z "$BO_MENU_ONLINE_FILE" ] || rm -f "$BO_MENU_ONLINE_FILE"
  BO_MENU_ONLINE_PID=""
  BO_MENU_ONLINE_FILE=""
}

bo_menu_is_online() {
  local username="$1"
  awk -F '\t' -v username="$username" '$1 == username { found=1 } END { exit !found }' <<<"$BO_MENU_ONLINE_USERS"
}

bo_menu_format_expiry() {
  local epoch="$1"
  LC_TIME=C date -u -d "@$epoch" '+%-d %b %Y' 2>/dev/null || printf '%s' "$epoch"
}

bo_menu_status_value() {
  local label="$1" value
  value="$(awk -F ': ' -v label="$label" '$1 == label { print $2; exit }' <<<"$BO_MENU_STATUS")"
  printf '%s\n' "${value:-unknown}"
}

bo_menu_api_action() {
  if [ "$(bo_menu_status_value 'user api')" = disabled ]; then
    printf 'Enable\n'
  else
    printf 'Disable\n'
  fi
}

bo_menu_collect_status() {
  local output status=0
  output="$(mktemp)" || return 1
  bo_menu_load bo_status_cmd status.sh
  bo_status_cmd >"$output" 2>/dev/null || status=$?
  BO_MENU_STATUS="$(cat "$output")"
  rm -f "$output"
  [ -n "$BO_MENU_STATUS" ] || BO_MENU_STATUS="overall: unknown"
  return "$status"
}

bo_menu_screen_title() {
  case "$BO_MENU_SCREEN" in
    dashboard) printf 'Dashboard\n' ;;
    users) printf 'Users\n' ;;
    user-detail) printf 'Users > %s\n' "$BO_MENU_SELECTED_USER" ;;
    xray) printf 'Xray\n' ;;
    certs) printf 'Certificates\n' ;;
    config) printf 'Config\n' ;;
    api) printf 'API\n' ;;
    update) printf 'Update\n' ;;
    *) printf '%s\n' "$BO_MENU_SCREEN" ;;
  esac
}

bo_menu_rows() {
  case "$BO_MENU_SCREEN" in
    dashboard)
      printf '%s\n' Status Users Xray Certificates Config API Update
      ;;
    users) bo_menu_rows_users ;;
    user-detail)
      printf '%s\n' Link 'Modify duration'
      if [ "$BO_MENU_SELECTED_USER_STATUS" = active ]; then
        printf 'Lock\n'
      elif [ "$BO_MENU_SELECTED_USER_STATUS" = locked ]; then
        printf 'Unlock\n'
      fi
      printf 'Remove\n'
      ;;
    xray)
      printf '%s\n' 'Install latest' 'Update latest' 'Current version' 'Change version'
      ;;
    certs)
      printf '%s\n' Status Issue Renew 'Change domain'
      ;;
    config) bo_menu_rows_config ;;
    api)
      printf '%s\n' "$(bo_menu_api_action)" Status 'New token'
      ;;
    update)
      printf '%s\n' 'Check for update' 'Install update'
      ;;
  esac
}

bo_menu_rows_users() {
  local username uuid level status created_at expires_at updated_at online
  printf 'Add user\n'
  printf 'Remove expired\n'
  while IFS=$'\t' read -r username uuid level status created_at expires_at updated_at; do
    [ -n "$username" ] || continue
    online=offline
    bo_menu_is_online "$username" && online=online
    printf '%-18s %-8s %-20s %s\n' "$username" "$status" "$(bo_menu_format_expiry "$expires_at")" "$online"
  done <<<"$BO_MENU_USERS"
}

bo_menu_rows_config() {
  local profile state
  printf 'Reload current\n'
  while IFS=$'\t' read -r profile state; do
    [ -n "$profile" ] || continue
    printf '%-24s %s\n' "$profile" "$state"
  done <<<"$BO_MENU_PROFILES"
}

bo_menu_row_count() {
  local rows
  rows="$(bo_menu_rows)"
  if [ -z "$rows" ]; then
    printf '0\n'
  else
    awk 'END { print NR }' <<<"$rows"
  fi
}

bo_menu_card_state() {
  case "$1" in
    ok|usable|active|running) printf 'ok\n' ;;
    disabled|unknown) printf 'warning\n' ;;
    *) printf 'fail\n' ;;
  esac
}

bo_menu_certificate_summary() {
  local fullchain enddate
  fullchain="${BLACKOUT_SSL_FULLCHAIN:-${BLACKOUT_SSL_DIR:-${BLACKOUT_ETC_DIR:-/etc/blackout}/ssl}/fullchain.pem}"
  if [ ! -s "$fullchain" ]; then
    printf 'missing\tfail\n'
    return
  fi
  enddate="$(openssl x509 -in "$fullchain" -noout -enddate 2>/dev/null | cut -d= -f2- || true)"
  if [ -n "$enddate" ]; then
    enddate="$(LC_TIME=C date -u -d "$enddate" '+%-d %b %Y' 2>/dev/null || printf '%s' "$enddate")"
  fi
  if ! openssl x509 -in "$fullchain" -noout -checkend 604800 >/dev/null 2>&1; then
    printf '%s\twarning\n' "${enddate:-expiring}"
  else
    printf '%s\tok\n' "${enddate:-valid}"
  fi
}

bo_menu_update_summary() {
  local version="${BLACKOUT_VERSION:-dev}" repo branch remote
  if [ "$version" = dev ]; then
    printf 'dev\twarning\n'
  elif declare -F bo_update_remote_version >/dev/null 2>&1 || [ -r "$BLACKOUT_LIB_DIR/update.sh" ]; then
    bo_menu_load bo_update_remote_version update.sh
    repo="$(bo_update_repo)"
    branch="$(bo_update_branch)"
    remote="$( ( bo_update_remote_version "$repo" "$branch" ) 2>/dev/null || true)"
    if [ -z "$remote" ]; then
      printf '%s\tunknown\n' "${version:0:12}"
    elif [ "$version" = "$remote" ]; then
      printf '%s\tlatest\n' "${version:0:12}"
    else
      printf '%s\twarning\n' "${version:0:12}"
    fi
  else
    printf '%s\tunknown\n' "${version:0:12}"
  fi
}

bo_menu_user_count() {
  if declare -F bo_db_query >/dev/null 2>&1; then
    bo_db_query 'SELECT COUNT(*) FROM users;' 2>/dev/null || printf 'unknown\n'
  elif command -v sqlite3 >/dev/null 2>&1 && [ -f "${BLACKOUT_DB:-}" ]; then
    sqlite3 "$BLACKOUT_DB" 'SELECT COUNT(*) FROM users;' 2>/dev/null || printf 'unknown\n'
  else
    printf 'unknown\n'
  fi
}

bo_menu_profile() {
  if declare -F bo_setting_get >/dev/null 2>&1; then
    bo_setting_get profile 2>/dev/null || printf 'default\n'
  else
    printf 'unknown\n'
  fi
}

bo_menu_render_card_group() {
  local width="$1" variant="$2" tmp title value state file index=0
  shift 2
  tmp="$(mktemp -d)" || return 1
  while [ "$#" -ge 3 ]; do
    title="$1"
    value="$2"
    state="$3"
    shift 3
    printf -v file '%s/card-%02d' "$tmp" "$index"
    if [ "$variant" = compact ]; then
      bo_tui_card_compact "$title" "$value" "$state" "$width" >"$file"
    else
      bo_tui_card "$title" "$value" "$state" "$width" >"$file"
    fi
    index=$((index + 1))
  done
  paste -d ' ' "$tmp"/card-* 2>/dev/null || true
  rm -rf "$tmp"
}

bo_menu_render_cards() {
  local mode="${1:-wide}" xray nginx database api profile users certificate certificate_state update update_state width
  xray="$(bo_menu_status_value 'xray service')"
  nginx="$(bo_menu_status_value 'nginx service')"
  database="$(bo_menu_status_value database)"
  api="$(bo_menu_status_value 'user api')"
  profile="$(bo_menu_profile)"
  users="$(bo_menu_user_count)"
  IFS=$'\t' read -r certificate certificate_state <<<"$(bo_menu_certificate_summary)"
  IFS=$'\t' read -r update update_state <<<"$(bo_menu_update_summary)"
  if [ "$mode" = wide ]; then
    width=$(((BO_TUI_COLS - 3) / 4))
    bo_menu_render_card_group "$width" wide \
      XRAY "$xray" "$(bo_menu_card_state "$xray")" \
      NGINX "$nginx" "$(bo_menu_card_state "$nginx")" \
      DATABASE "$database" "$(bo_menu_card_state "$database")" \
      CERTIFICATE "$certificate" "$certificate_state"
    bo_menu_render_card_group "$width" wide \
      API "$api" "$(bo_menu_card_state "$api")" \
      PROFILE "${profile:-default}" ok \
      USERS "$users" ok \
      UPDATE "$update" "$update_state"
  else
    width=$(((BO_TUI_COLS - 1) / 2))
    bo_menu_render_card_group "$width" compact XRAY "$xray" "$(bo_menu_card_state "$xray")" NGINX "$nginx" "$(bo_menu_card_state "$nginx")"
    bo_menu_render_card_group "$width" compact DATABASE "$database" "$(bo_menu_card_state "$database")" CERTIFICATE "$certificate" "$certificate_state"
    bo_menu_render_card_group "$width" compact API "$api" "$(bo_menu_card_state "$api")" PROFILE "${profile:-default}" ok
    bo_menu_render_card_group "$width" compact USERS "$users" ok UPDATE "$update" "$update_state"
  fi
}

bo_menu_context() {
  local row="$1"
  case "$BO_MENU_SCREEN:$row" in
    dashboard:Status) printf 'Inspect health checks for the complete Blackout stack.' ;;
    dashboard:Users) printf 'Create, inspect, modify, lock, and remove Xray users.' ;;
    dashboard:Xray) printf 'Manage the installed Xray core and version.' ;;
    dashboard:Certificates) printf 'Issue and renew acme.sh TLS certificates.' ;;
    dashboard:Config) printf 'Inspect, switch, and reload configuration profiles.' ;;
    dashboard:API) printf 'Manage the optional Blackout HTTP API.' ;;
    dashboard:Update) printf 'Compare and install the latest Blackout revision.' ;;
    users:'Add user') printf 'Create a VLESS user and add it to every managed inbound.' ;;
    users:*) printf 'Account: %s\nSelect to manage this user.' "${row%% *}" ;;
    user-detail:*) printf 'User: %s\nStatus: %s\nAction: %s' "$BO_MENU_SELECTED_USER" "$BO_MENU_SELECTED_USER_STATUS" "$row" ;;
    xray:*) printf 'Installed: %s\nService: %s' "$(bo_menu_xray_version)" "$(bo_menu_status_value 'xray service')" ;;
    certs:*) printf 'Domain: %s\nAction: %s' "$(bo_menu_domain)" "$row" ;;
    config:*) printf 'Active profile: %s\nSelection: %s' "$(bo_menu_profile)" "$row" ;;
    api:*) printf 'API state: %s\nAction: %s' "$(bo_menu_status_value 'user api')" "$row" ;;
    update:*) printf 'Installed: %s\nAction: %s' "$BLACKOUT_VERSION" "$row" ;;
    *) printf 'Select %s and press Enter.' "$row" ;;
  esac
}

bo_menu_domain() {
  if declare -F bo_setting_get >/dev/null 2>&1; then
    bo_setting_get domain 2>/dev/null || printf 'unset\n'
  else
    printf 'unset\n'
  fi
}

bo_menu_xray_version() {
  local version
  bo_menu_load bo_xray_cmd xray.sh
  version="$(bo_xray_cmd current 2>/dev/null | head -n 1 || true)"
  printf '%s\n' "${version:-unknown}"
}

bo_menu_render_rows() {
  local index=0 row marker style reset
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    marker='  '
    style=''
    reset=''
    if [ "$index" -eq "$BO_MENU_SELECTION" ]; then
      marker='› '
      style="$(bo_color selected)"
      reset="$(bo_color reset)"
    fi
    printf '%s%s%-28s%s\n' "$style" "$marker" "$row" "$reset"
    index=$((index + 1))
  done <<<"$(bo_menu_rows)"
}

bo_menu_selected_row() {
  sed -n "$((BO_MENU_SELECTION + 1))p" <<<"$(bo_menu_rows)"
}

bo_menu_render_help() {
  bo_tui_panel 'Keyboard shortcuts' $'↑/k  Move up\n↓/j  Move down\nEnter Select\nr     Refresh\nb/Esc Back\nq     Quit\n?     Toggle help' 52
}

bo_menu_render_small() {
  printf '\033[2J\033[H'
  bo_menu_render_title
  printf '\nTerminal too small (%sx%s). Resize to at least 56x18.\n' "$BO_TUI_COLS" "$BO_TUI_ROWS"
  bo_tui_footer 'r Refresh  q Quit'
}

bo_menu_render_title() {
  local title
  title="$(bo_menu_screen_title)"
  printf '%sBlackout > %s%s\n' "$(bo_color cyan)" "$title" "$(bo_color reset)"
}

bo_menu_render() {
  local title selected mode
  bo_tui_dimensions
  mode="$(bo_tui_layout_mode)"
  if [ "$mode" = small ]; then
    bo_menu_render_small
    return
  fi
  title="$(bo_menu_screen_title)"
  selected="$(bo_menu_selected_row)"
  printf '\033[2J\033[H'
  bo_menu_render_title
  printf '\n'
  if [ "$BO_MENU_SCREEN" = dashboard ]; then
    bo_menu_render_cards "$mode"
    printf '\n'
  fi
  if [ "$BO_MENU_SHOW_HELP" = 1 ]; then
    bo_menu_render_help
  elif [ -n "$BO_MENU_RESULT" ]; then
    bo_tui_panel Result "$BO_MENU_RESULT" 70
  else
    bo_menu_render_rows
    if [ "$mode" = wide ]; then
      printf '\n'
      bo_tui_panel Context "$(bo_menu_context "$selected")" 70
    fi
  fi
  printf '\n'
  bo_tui_footer '↑/↓ Navigate  Enter Select  r Refresh  b/Esc Back  ? Help  q Quit'
}

bo_menu_open() {
  BO_MENU_SCREEN="$1"
  BO_MENU_SELECTION=0
  BO_MENU_RESULT=""
  case "$BO_MENU_SCREEN" in
    users) bo_menu_collect_users; bo_menu_online_start ;;
    config) bo_menu_collect_profiles ;;
  esac
}

bo_menu_back() {
  if [ "$BO_MENU_SHOW_HELP" = 1 ]; then
    BO_MENU_SHOW_HELP=0
  elif [ -n "$BO_MENU_RESULT" ]; then
    BO_MENU_RESULT=""
  elif [ "$BO_MENU_SCREEN" = user-detail ]; then
    bo_menu_open users
  elif [ "$BO_MENU_SCREEN" != dashboard ]; then
    bo_menu_online_stop
    bo_menu_open dashboard
  else
    BO_MENU_RUNNING=0
  fi
}

bo_menu_activate_dashboard() {
  case "$(bo_menu_selected_row)" in
    Status) BO_MENU_RESULT="$BO_MENU_STATUS" ;;
    Users) bo_menu_open users ;;
    Xray) bo_menu_open xray ;;
    Certificates) bo_menu_open certs ;;
    Config) bo_menu_open config ;;
    API) bo_menu_open api ;;
    Update) bo_menu_open update ;;
  esac
}

bo_menu_run_action() {
  local title="$1" output status=0
  shift
  output="$(bo_tui_run "$title" "$@")" || status=$?
  if [ "$status" -eq 0 ]; then
    BO_MENU_RESULT="Completed: $title"
  else
    BO_MENU_RESULT="Failed: $title"
  fi
  [ -z "$output" ] || BO_MENU_RESULT+=$'\n'"$output"
  return "$status"
}

bo_menu_confirm_action() {
  local title="$1"
  shift
  bo_tui_confirm "$title?" || {
    BO_MENU_RESULT="Cancelled: $title"
    return 0
  }
  bo_menu_run_action "$title" "$@"
}

bo_menu_user_from_selection() {
  local row
  row="$(sed -n "$((BO_MENU_SELECTION - 1))p" <<<"$BO_MENU_USERS")"
  BO_MENU_SELECTED_USER="${row%%$'\t'*}"
  row="${row#*$'\t'}"
  row="${row#*$'\t'}"
  row="${row#*$'\t'}"
  BO_MENU_SELECTED_USER_STATUS="${row%%$'\t'*}"
}

bo_menu_refresh_selected_user() {
  local username uuid level status created_at expires_at updated_at
  bo_menu_collect_users
  while IFS=$'\t' read -r username uuid level status created_at expires_at updated_at; do
    if [ "$username" = "$BO_MENU_SELECTED_USER" ]; then
      BO_MENU_SELECTED_USER_STATUS="$status"
      return
    fi
  done <<<"$BO_MENU_USERS"
}

bo_menu_add_user() {
  local username duration uuid expires_at
  bo_menu_load bo_user_add users.sh
  username="$(bo_tui_input Username)" || return 0
  [ -n "$username" ] || {
    BO_MENU_RESULT='Cancelled: Add user'
    return 0
  }
  duration="$(bo_tui_input 'Duration (12h, 7d, 1m)' 30d)" || return 0
  expires_at="$(bo_expiry_epoch "$duration")" || {
    BO_MENU_RESULT="Invalid duration: $duration"
    return 1
  }
  uuid="$(bo_user_generate_uuid)" || return 1
  bo_menu_run_action "Add user $username" bo_user_add "$username" "$uuid" "$expires_at"
}

bo_menu_activate_users() {
  if [ "$BO_MENU_SELECTION" -eq 0 ]; then
    bo_menu_add_user || true
    bo_menu_collect_users
    return
  fi
  if [ "$BO_MENU_SELECTION" -eq 1 ]; then
    bo_menu_load bo_user_cmd users.sh
    bo_menu_confirm_action 'Remove expired users' bo_user_cmd remove-expired || true
    bo_menu_collect_users
    return
  fi
  bo_menu_user_from_selection
  [ -n "$BO_MENU_SELECTED_USER" ] || return
  bo_menu_open user-detail
}

bo_menu_activate_user_detail() {
  local row duration
  row="$(bo_menu_selected_row)"
  bo_menu_load bo_user_cmd users.sh
  case "$row" in
    Link) bo_menu_run_action "Links for $BO_MENU_SELECTED_USER" bo_user_cmd link "$BO_MENU_SELECTED_USER" || true ;;
    'Modify duration')
      duration="$(bo_tui_input 'New duration (12h, 7d, 1m)' 30d)" || return
      bo_menu_run_action "Modify $BO_MENU_SELECTED_USER" bo_user_modify_duration "$BO_MENU_SELECTED_USER" "$duration" || true
      bo_menu_refresh_selected_user
      ;;
    Lock)
      bo_menu_confirm_action "Lock user $BO_MENU_SELECTED_USER" bo_user_cmd lock "$BO_MENU_SELECTED_USER" || true
      bo_menu_refresh_selected_user
      ;;
    Unlock)
      bo_menu_run_action "Unlock user $BO_MENU_SELECTED_USER" bo_user_cmd unlock "$BO_MENU_SELECTED_USER" || true
      bo_menu_refresh_selected_user
      ;;
    Remove)
      bo_menu_confirm_action "Remove user $BO_MENU_SELECTED_USER" bo_user_cmd remove "$BO_MENU_SELECTED_USER" || true
      [ "${BO_MENU_RESULT#Completed:}" = "$BO_MENU_RESULT" ] || bo_menu_open users
      ;;
  esac
}

bo_menu_activate_xray() {
  local row version
  row="$(bo_menu_selected_row)"
  bo_menu_load bo_xray_cmd xray.sh
  case "$row" in
    'Install latest') bo_menu_confirm_action 'Install latest Xray' bo_xray_cmd install latest || true ;;
    'Update latest') bo_menu_confirm_action 'Update Xray' bo_xray_cmd update || true ;;
    'Current version') bo_menu_run_action 'Current Xray version' bo_xray_cmd current || true ;;
    'Change version')
      version="$(bo_tui_input 'Xray version')" || return
      [ -n "$version" ] && bo_menu_confirm_action "Install Xray $version" bo_xray_cmd version "$version" || true
      ;;
  esac
}

bo_menu_activate_certs() {
  local row email domain
  row="$(bo_menu_selected_row)"
  bo_menu_load bo_cert_cmd certs.sh
  case "$row" in
    Status) bo_menu_run_action 'Certificate status' bo_cert_cmd status || true ;;
    Issue)
      email="$(bo_tui_input 'ACME email')" || return
      domain="$(bo_tui_input Domain "$(bo_menu_domain)")" || return
      bo_menu_confirm_action "Issue certificate for $domain" bo_cert_cmd issue "$email" "$domain" || true
      ;;
    Renew) bo_menu_confirm_action 'Renew certificate' bo_cert_cmd renew || true ;;
    'Change domain')
      domain="$(bo_tui_input 'New domain' "$(bo_menu_domain)")" || return
      bo_menu_confirm_action "Change domain to $domain" bo_cert_cmd change-domain "$domain" || true
      ;;
  esac
}

bo_menu_activate_config() {
  local profile
  bo_menu_load bo_config_cmd configs.sh
  if [ "$BO_MENU_SELECTION" -eq 0 ]; then
    bo_menu_confirm_action 'Reload current config' bo_config_cmd reload || true
    return
  fi
  profile="$(sed -n "${BO_MENU_SELECTION}p" <<<"$BO_MENU_PROFILES")"
  profile="${profile%%$'\t'*}"
  [ -n "$profile" ] && bo_menu_confirm_action "Switch config to $profile" bo_config_cmd switch "$profile" || true
}

bo_menu_api_status() {
  bo_api_control_cmd status || true
}

bo_menu_activate_api() {
  local row
  row="$(bo_menu_selected_row)"
  bo_menu_load bo_api_control_cmd api.sh
  case "$row" in
    Enable)
      bo_menu_run_action 'Enable API' bo_api_control_cmd enable || true
      bo_menu_collect_status || true
      ;;
    Disable)
      bo_menu_confirm_action 'Disable API' bo_api_control_cmd disable || true
      bo_menu_collect_status || true
      ;;
    Status)
      bo_menu_run_action 'API status' bo_menu_api_status || true
      bo_menu_collect_status || true
      ;;
    'New token') bo_menu_confirm_action 'Rotate API token' bo_api_control_cmd token || true ;;
  esac
}

bo_menu_activate_update() {
  local row
  row="$(bo_menu_selected_row)"
  bo_menu_load bo_update_cmd update.sh
  case "$row" in
    'Check for update') bo_menu_run_action 'Check for update' bo_update_cmd check || true ;;
    'Install update') bo_menu_confirm_action 'Install Blackout update' bo_update_cmd run || true ;;
  esac
}

bo_menu_activate() {
  case "$BO_MENU_SCREEN" in
    dashboard) bo_menu_activate_dashboard ;;
    users) bo_menu_activate_users ;;
    user-detail) bo_menu_activate_user_detail ;;
    xray) bo_menu_activate_xray ;;
    certs) bo_menu_activate_certs ;;
    config) bo_menu_activate_config ;;
    api) bo_menu_activate_api ;;
    update) bo_menu_activate_update ;;
  esac
}

bo_menu_tick() {
  local count
  bo_menu_collect_status || true
  case "$BO_MENU_SCREEN" in
    users) bo_menu_collect_users; bo_menu_online_poll ;;
    config) bo_menu_collect_profiles ;;
  esac
  count="$(bo_menu_row_count)"
  BO_MENU_SELECTION="$(bo_tui_clamp_selection "$BO_MENU_SELECTION" "$count")"
}

bo_menu_handle_key() {
  local key="$1" count number
  if [ "$BO_MENU_SHOW_HELP" = 1 ]; then
    case "$key" in back|help|enter) BO_MENU_SHOW_HELP=0 ;; quit) BO_MENU_RUNNING=0 ;; esac
    return
  fi
  if [ -n "$BO_MENU_RESULT" ]; then
    case "$key" in back|enter) BO_MENU_RESULT="" ;; quit) BO_MENU_RUNNING=0 ;; refresh) bo_menu_tick ;; esac
    return
  fi
  count="$(bo_menu_row_count)"
  case "$key" in
    up)
      BO_MENU_SELECTION="$(bo_tui_clamp_selection "$((BO_MENU_SELECTION - 1))" "$count")"
      ;;
    down)
      BO_MENU_SELECTION="$(bo_tui_clamp_selection "$((BO_MENU_SELECTION + 1))" "$count")"
      ;;
    enter) bo_menu_activate ;;
    refresh) bo_menu_tick ;;
    help) BO_MENU_SHOW_HELP=1 ;;
    back) bo_menu_back ;;
    quit) BO_MENU_RUNNING=0 ;;
    number:*)
      number="${key#number:}"
      if [ "$number" -le "$count" ]; then
        BO_MENU_SELECTION=$((number - 1))
        bo_menu_activate
      fi
      ;;
  esac
}

bo_menu() {
  local raw key
  bo_tui_enter || return 1
  trap 'bo_menu_online_stop; bo_tui_leave' EXIT
  trap 'bo_menu_online_stop; bo_tui_leave; exit 130' INT TERM HUP
  trap ':' WINCH
  bo_menu_init
  while [ "$BO_MENU_RUNNING" = 1 ]; do
    bo_menu_render
    if raw="$(bo_tui_read_key "$BO_MENU_KEY_TIMEOUT")"; then
      key="$(bo_tui_decode_key "$raw")"
      bo_menu_handle_key "$key"
    fi
  done
  bo_menu_online_stop
  bo_tui_leave
  trap - EXIT INT TERM HUP WINCH
}
