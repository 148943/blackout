#!/usr/bin/env bash

if ! declare -F bo_fail >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/common.sh"
fi

BLACKOUT_NGINX_SITE_NAME="${BLACKOUT_NGINX_SITE_NAME:-blackout}"
BLACKOUT_NGINX_AVAILABLE_DIR="${BLACKOUT_NGINX_AVAILABLE_DIR:-/etc/nginx/sites-available}"
BLACKOUT_NGINX_ENABLED_DIR="${BLACKOUT_NGINX_ENABLED_DIR:-/etc/nginx/sites-enabled}"

bo_nginx_available_path() {
  printf '%s/%s\n' "$BLACKOUT_NGINX_AVAILABLE_DIR" "$BLACKOUT_NGINX_SITE_NAME"
}

bo_nginx_enabled_path() {
  printf '%s/%s\n' "$BLACKOUT_NGINX_ENABLED_DIR" "$BLACKOUT_NGINX_SITE_NAME"
}

bo_nginx_install_site() {
  local source="${1:?nginx config path required}" available enabled
  available="$(bo_nginx_available_path)"
  enabled="$(bo_nginx_enabled_path)"

  mkdir -p "$BLACKOUT_NGINX_AVAILABLE_DIR" "$BLACKOUT_NGINX_ENABLED_DIR"
  install -m 0644 "$source" "$available"
  ln -sfn "$available" "$enabled"
}

bo_nginx_snapshot_site() {
  local dest="${1:?snapshot dir required}" available enabled
  available="$(bo_nginx_available_path)"
  enabled="$(bo_nginx_enabled_path)"
  mkdir -p "$dest"

  if [ -e "$available" ]; then
    cp -a "$available" "$dest/available"
    printf '1\n' >"$dest/had_available"
  else
    printf '0\n' >"$dest/had_available"
  fi

  if [ -L "$enabled" ]; then
    readlink "$enabled" >"$dest/enabled_link"
    printf 'link\n' >"$dest/enabled_type"
  elif [ -e "$enabled" ]; then
    cp -a "$enabled" "$dest/enabled_file"
    printf 'file\n' >"$dest/enabled_type"
  else
    printf 'none\n' >"$dest/enabled_type"
  fi
}

bo_nginx_restore_site() {
  local snapshot="${1:?snapshot dir required}" available enabled type
  available="$(bo_nginx_available_path)"
  enabled="$(bo_nginx_enabled_path)"
  mkdir -p "$BLACKOUT_NGINX_AVAILABLE_DIR" "$BLACKOUT_NGINX_ENABLED_DIR"

  if [ "$(cat "$snapshot/had_available")" = "1" ]; then
    cp -a "$snapshot/available" "$available"
  else
    rm -f "$available"
  fi

  type="$(cat "$snapshot/enabled_type")"
  rm -f "$enabled"
  case "$type" in
    link) ln -s "$(cat "$snapshot/enabled_link")" "$enabled" ;;
    file) cp -a "$snapshot/enabled_file" "$enabled" ;;
    none) ;;
  esac
}

bo_nginx_test() {
  nginx -t
}

bo_nginx_reload() {
  systemctl reload nginx
}
