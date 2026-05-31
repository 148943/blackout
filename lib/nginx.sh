#!/usr/bin/env bash

if ! declare -F bo_fail >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/common.sh"
fi

BLACKOUT_NGINX_SITE_NAME="${BLACKOUT_NGINX_SITE_NAME:-blackout}"
BLACKOUT_NGINX_AVAILABLE_DIR="${BLACKOUT_NGINX_AVAILABLE_DIR:-/etc/nginx/sites-available}"
BLACKOUT_NGINX_ENABLED_DIR="${BLACKOUT_NGINX_ENABLED_DIR:-/etc/nginx/sites-enabled}"

bo_nginx_install_site() {
  local source="${1:?nginx config path required}" available enabled
  available="$BLACKOUT_NGINX_AVAILABLE_DIR/$BLACKOUT_NGINX_SITE_NAME"
  enabled="$BLACKOUT_NGINX_ENABLED_DIR/$BLACKOUT_NGINX_SITE_NAME"

  mkdir -p "$BLACKOUT_NGINX_AVAILABLE_DIR" "$BLACKOUT_NGINX_ENABLED_DIR"
  install -m 0644 "$source" "$available"
  ln -sfn "$available" "$enabled"
}

bo_nginx_test() {
  nginx -t
}

bo_nginx_reload() {
  systemctl reload nginx
}
