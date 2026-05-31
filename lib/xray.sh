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
  local version="$1" dest="$2" arch asset url zip digest
  [ "$version" = latest ] && version="$(bo_xray_latest_version)"
  arch="$(uname -m)"
  asset="$(bo_xray_asset_for_arch "$arch")" || bo_fail "unsupported architecture: $arch"
  url="https://github.com/XTLS/Xray-core/releases/download/$version/$asset"
  zip="$dest/$asset"
  digest="$zip.dgst"
  mkdir -p "$dest"
  bo_trace "download: $url" >&2
  curl -fL "$url" -o "$zip"
  if curl -fsSL "$(bo_xray_digest_url "$version" "$asset")" -o "$digest"; then
    bo_xray_verify_zip "$zip" "$digest" "$asset"
  else
    bo_warn "digest unavailable for $asset; continuing without checksum verification"
  fi
  printf '%s\n' "$zip"
}

bo_xray_digest_url() {
  local version="$1" asset="$2"
  printf 'https://github.com/XTLS/Xray-core/releases/download/%s/%s.dgst\n' "$version" "$asset"
}

bo_xray_verify_zip() {
  local zip="$1" digest_file="$2" asset="$3" expected actual
  expected="$(grep -i 'SHA256' "$digest_file" | grep -F "$asset" | grep -Eo '[A-Fa-f0-9]{64}' | head -n 1 | tr 'A-F' 'a-f' || true)"
  if [ -z "$expected" ]; then
    bo_warn "digest file does not include SHA256 for $asset; continuing without checksum verification"
    return 0
  fi
  actual="$(sha256sum "$zip" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    printf 'checksum verification failed for %s\n' "$asset" >&2
    return 1
  fi
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

bo_xray_stat_name() {
  local username="$1" direction="$2"
  case "$direction" in
    uplink) printf 'user>>>%s>>>traffic>>>uplink\n' "$username" ;;
    downlink) printf 'user>>>%s>>>traffic>>>downlink\n' "$username" ;;
    *) return 1 ;;
  esac
}

bo_xray_query_stat() {
  local name="$1"
  bo_xray_api statsquery --pattern "$name" --reset=false
}

bo_xray_user_stats() {
  local username="$1"
  bo_xray_query_stat "user>>>$username>>>traffic>>>"
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
