#!/usr/bin/env bash

bo_xray_asset_for_arch() {
  case "$1" in
    x86_64|amd64) printf 'Xray-linux-64.zip\n' ;;
    aarch64|arm64) printf 'Xray-linux-arm64-v8a.zip\n' ;;
    armv7l|armhf) printf 'Xray-linux-arm32-v7a.zip\n' ;;
    *) return 1 ;;
  esac
}

bo_xray_latest_version() {
  curl -fsSLI -o /dev/null -w '%{url_effective}\n' https://github.com/XTLS/Xray-core/releases/latest | sed 's#.*/##'
}

bo_xray_download() {
  local version="$1" dest="$2" arch asset url
  [ "$version" = latest ] && version="$(bo_xray_latest_version)"
  arch="$(uname -m)"
  asset="$(bo_xray_asset_for_arch "$arch")" || bo_fail "unsupported architecture: $arch"
  url="https://github.com/XTLS/Xray-core/releases/download/$version/$asset"
  mkdir -p "$dest"
  bo_trace "download: $url"
  curl -fL "$url" -o "$dest/$asset"
  printf '%s\n' "$dest/$asset"
}

bo_xray_install_version() {
  bo_need_root
  local version="${1:-latest}" tmp zip
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  zip="$(bo_xray_download "$version" "$tmp")"
  unzip -o "$zip" -d "$tmp/xray" >/dev/null
  install -Dm755 "$tmp/xray/xray" /usr/local/bin/xray
  [ -f "$tmp/xray/geoip.dat" ] && install -Dm644 "$tmp/xray/geoip.dat" /usr/local/share/xray/geoip.dat
  [ -f "$tmp/xray/geosite.dat" ] && install -Dm644 "$tmp/xray/geosite.dat" /usr/local/share/xray/geosite.dat
  systemctl restart xray
}

bo_xray_api() {
  local service="$1"; shift
  xray api "$service" --server=127.0.0.1:60001 "$@"
}

bo_xray_cmd() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    install) bo_xray_install_version "${1:-latest}" ;;
    update) bo_xray_install_version latest ;;
    version) bo_xray_install_version "${1:?version required}" ;;
    current) xray version ;;
    *) bo_fail "unknown xray command: ${cmd:-}" ;;
  esac
}
