#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${BLACKOUT_ROOT_DIR:-$ROOT_DIR}"
BLACKOUT_LIB_DIR="$ROOT_DIR/lib"

# shellcheck disable=SC1091
. "$ROOT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$ROOT_DIR/lib/db.sh"
# shellcheck disable=SC1091
. "$ROOT_DIR/lib/xray.sh"
# shellcheck disable=SC1091
. "$ROOT_DIR/lib/certs.sh"
# shellcheck disable=SC1091
. "$ROOT_DIR/lib/configs.sh"

bo_install_run() {
  if [ "${BLACKOUT_DRY_RUN:-0}" = "1" ]; then
    printf '%s\n' "$*" >>"${BLACKOUT_DRY_RUN_LOG:-/dev/stderr}"
  else
    "$@"
  fi
}

bo_install_need_root() {
  if [ "${BLACKOUT_DRY_RUN:-0}" = "1" ]; then
    return 0
  fi
  bo_need_root
}

bo_install_check_debian12() {
  local os_release="${BLACKOUT_OS_RELEASE:-/etc/os-release}"
  # shellcheck disable=SC1090
  . "$os_release"
  [ "${VERSION_ID:-}" = "12" ] || bo_fail "Debian 12 required"
}

bo_install_apt_packages() {
  bo_install_run apt-get update
  bo_install_run apt-get install -y curl unzip jq sqlite3 nginx socat cron ca-certificates git uuid-runtime
}

bo_install_copy_tree() {
  local src="$1" install_dir="$2" bin_path="$3"
  [ -n "$install_dir" ] && [ "$install_dir" != "/" ] || bo_fail "unsafe install dir: $install_dir"
  install -Dm755 "$src/blackout" "$bin_path"
  mkdir -p "$install_dir"
  rm -rf "$install_dir/lib" "$install_dir/configs"
  cp -a "$src/lib" "$install_dir/lib"
  cp -a "$src/configs" "$install_dir/configs"
}

bo_install_expire_cron() {
  local cron_file="${BLACKOUT_EXPIRE_CRON:-/etc/cron.d/blackout-expire}" bin_path="${BLACKOUT_BIN_PATH:-/usr/local/bin/blackout}"
  mkdir -p "$(dirname "$cron_file")"
  cat >"$cron_file" <<EOF_CRON
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

*/5 * * * * root $bin_path user expire >>/var/log/blackout-expire.log 2>&1
EOF_CRON
  chmod 0644 "$cron_file"
  bo_log "installed expiry cron: $cron_file"
}

bo_install_write_env() {
  local env_file="$1" install_dir="$2" lib_dir="$3" config_dir="$4" db_path="$5" etc_dir="${6:-/etc/blackout}" state_dir="${7:-/var/lib/blackout}" xray_config="${8:-/etc/xray/config.json}"
  mkdir -p "$(dirname "$env_file")"
  cat >"$env_file" <<EOF_ENV
BLACKOUT_REPO="${BLACKOUT_REPO:-https://github.com/148943/blackout.git}"
BLACKOUT_BRANCH="${BLACKOUT_BRANCH:-master}"
BLACKOUT_VERSION="${BLACKOUT_VERSION:-dev}"
BLACKOUT_INSTALL_DIR="$install_dir"
BLACKOUT_LIB_DIR="$lib_dir"
BLACKOUT_CONFIG_DIR="$config_dir"
BLACKOUT_ETC_DIR="$etc_dir"
BLACKOUT_STATE_DIR="$state_dir"
BLACKOUT_SSL_DIR="$etc_dir/ssl"
BLACKOUT_DB="$db_path"
BLACKOUT_XRAY_CONFIG="$xray_config"
EOF_ENV
  if [ -n "${BLACKOUT_CF_TOKEN:-}" ]; then
    printf 'BLACKOUT_CF_TOKEN="%s"\n' "$(bo_cert_env_quote "$BLACKOUT_CF_TOKEN")" >>"$env_file"
  fi
  chmod 0600 "$env_file"
}

bo_install_prompt() {
  local __domain_var="$1" __email_var="$2" __domain_value __email_value
  read -r -p "Domain: " __domain_value
  read -r -p "ACME email: " __email_value
  printf -v "$__domain_var" '%s' "$__domain_value"
  printf -v "$__email_var" '%s' "$__email_value"
}

bo_install_prompt_cloudflare() {
  local __token_var="$1" __token_value
  read -r -p "Cloudflare API token: " __token_value
  printf -v "$__token_var" '%s' "$__token_value"
}

bo_install_xray_initial() {
  bo_xray_install_version latest
}

bo_install_prepare_xray() {
  local service_path="${BLACKOUT_XRAY_SERVICE_PATH:-/etc/systemd/system/xray.service}" config_path="${BLACKOUT_XRAY_CONFIG:-/etc/xray/config.json}"
  bo_xray_install_service "$service_path" "$config_path"
  BLACKOUT_XRAY_NO_RESTART=1 bo_install_xray_initial
  unset BLACKOUT_XRAY_NO_RESTART
  bo_config_switch vless-ws-nginx
  bo_install_expire_cron
}

bo_install_main() {
  local domain email cf_token
  local install_dir="${BLACKOUT_INSTALL_DIR:-/opt/blackout}"
  local lib_dir="${BLACKOUT_INSTALLED_LIB_DIR:-$install_dir/lib}"
  local config_dir="${BLACKOUT_INSTALLED_CONFIG_DIR:-$install_dir/configs}"
  local etc_dir="${BLACKOUT_ETC_DIR:-/etc/blackout}"
  local state_dir="${BLACKOUT_STATE_DIR:-/var/lib/blackout}"
  local db_path="${BLACKOUT_DB:-$state_dir/blackout.db}"
  local bin_path="${BLACKOUT_BIN_PATH:-/usr/local/bin/blackout}"
  local env_file="${BLACKOUT_ENV:-$etc_dir/blackout.env}"
  local xray_config="${BLACKOUT_XRAY_CONFIG:-/etc/xray/config.json}"
  local xray_service_path="${BLACKOUT_XRAY_SERVICE_PATH:-/etc/systemd/system/xray.service}"

  bo_install_need_root
  bo_install_check_debian12
  bo_install_apt_packages

  mkdir -p "$install_dir" "$etc_dir/ssl" "$state_dir" "$(dirname "$xray_config")"
  bo_install_copy_tree "$ROOT_DIR" "$install_dir" "$bin_path"
  bo_install_prompt domain email
  if [[ "$domain" == \*.* ]]; then
    bo_install_prompt_cloudflare cf_token
    BLACKOUT_CF_TOKEN="$cf_token"
    export BLACKOUT_CF_TOKEN
  fi
  bo_install_write_env "$env_file" "$install_dir" "$lib_dir" "$config_dir" "$db_path" "$etc_dir" "$state_dir" "$xray_config"

  BLACKOUT_LIB_DIR="$lib_dir"
  BLACKOUT_CONFIG_DIR="$config_dir"
  BLACKOUT_ETC_DIR="$etc_dir"
  BLACKOUT_STATE_DIR="$state_dir"
  BLACKOUT_DB="$db_path"
  BLACKOUT_XRAY_CONFIG="$xray_config"
  BLACKOUT_XRAY_SERVICE_PATH="$xray_service_path"
  BLACKOUT_BIN_PATH="$bin_path"
  BLACKOUT_ENV="$env_file"
  export BLACKOUT_LIB_DIR BLACKOUT_CONFIG_DIR BLACKOUT_ETC_DIR BLACKOUT_STATE_DIR BLACKOUT_DB BLACKOUT_XRAY_CONFIG BLACKOUT_XRAY_SERVICE_PATH BLACKOUT_BIN_PATH BLACKOUT_ENV

  bo_db_init
  bo_setting_set domain "$domain"
  bo_setting_set acme_email "$email"
  bo_setting_set ws_path "/vless"
  bo_acme_install "$email"
  bo_cert_issue "$email" "$domain"
  bo_install_prepare_xray
  systemctl enable --now xray nginx
  bo_log "install complete"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  bo_install_main "$@"
fi
