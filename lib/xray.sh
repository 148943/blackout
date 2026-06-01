#!/usr/bin/env bash

BLACKOUT_XRAY_CONFIG="${BLACKOUT_XRAY_CONFIG:-/etc/xray/config.json}"
BLACKOUT_XRAY_SERVICE_PATH="${BLACKOUT_XRAY_SERVICE_PATH:-/etc/systemd/system/xray.service}"

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
  local version="$1" dest="$2" arch asset url zip digest digest_status
  [ "$version" = latest ] && version="$(bo_xray_latest_version)"
  arch="$(uname -m)"
  asset="$(bo_xray_asset_for_arch "$arch")" || bo_fail "unsupported architecture: $arch"
  url="https://github.com/XTLS/Xray-core/releases/download/$version/$asset"
  zip="$dest/$asset"
  digest="$zip.dgst"
  mkdir -p "$dest"
  bo_trace "download: $url" >&2
  curl -fL "$url" -o "$zip"
  if bo_xray_download_digest "$(bo_xray_digest_url "$version" "$asset")" "$digest" "$asset"; then
    bo_xray_verify_zip "$zip" "$digest" "$asset" || return 1
  else
    digest_status=$?
    if [ "$digest_status" -eq 2 ]; then
      bo_warn "digest unavailable for $asset; continuing without checksum verification"
    else
      return 1
    fi
  fi
  printf '%s\n' "$zip"
}

bo_xray_download_digest() {
  local url="$1" digest="$2" asset="$3" http_status curl_status
  curl_status=0
  http_status="$(curl -sSL -o "$digest" -w '%{http_code}' "$url")" || curl_status=$?
  if [ "$curl_status" -ne 0 ]; then
    bo_warn "digest download failed for $asset (curl exit $curl_status)"
    return 1
  fi
  case "$http_status" in
    2??) return 0 ;;
    404) return 2 ;;
    *)
      bo_warn "digest download failed for $asset (HTTP ${http_status:-unknown})"
      return 1
      ;;
  esac
}

bo_xray_digest_url() {
  local version="$1" asset="$2"
  printf 'https://github.com/XTLS/Xray-core/releases/download/%s/%s.dgst\n' "$version" "$asset"
}

bo_xray_verify_zip() {
  local zip="$1" digest_file="$2" asset="$3" expected actual
  expected="$(grep -Ei 'SHA2-256|SHA256' "$digest_file" | grep -Eo '[A-Fa-f0-9]{64}' | head -n 1 | tr 'A-F' 'a-f' || true)"
  if [ -z "$expected" ]; then
    printf 'checksum digest not found for %s\n' "$asset" >&2
    return 1
  fi
  actual="$(sha256sum "$zip" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    printf 'checksum verification failed for %s\n' "$asset" >&2
    return 1
  fi
}

bo_xray_install_service() {
  local service_path="${1:-$BLACKOUT_XRAY_SERVICE_PATH}" config_path="${2:-$BLACKOUT_XRAY_CONFIG}" config_dir
  config_dir="$(dirname "$config_path")"
  mkdir -p "$(dirname "$service_path")" "$config_dir"
  cat >"$service_path" <<UNIT
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -config $config_path
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=false
ProtectHome=true
ProtectSystem=full
ReadWritePaths=$config_dir /etc/blackout /var/lib/blackout /dev/shm

[Install]
WantedBy=multi-user.target
UNIT
  if [ "${BLACKOUT_DRY_RUN:-0}" = "1" ]; then
    printf '%s\n' "systemctl daemon-reload" >>"${BLACKOUT_DRY_RUN_LOG:-/dev/stderr}"
  else
    systemctl daemon-reload
  fi
}

bo_xray_sync_active_users() {
  if ! declare -F bo_user_sync_active_to_xray >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/users.sh"
  fi
  bo_user_sync_active_to_xray
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
  [ "${BLACKOUT_XRAY_NO_RESTART:-0}" = "1" ] && return 0
  systemctl restart xray
  bo_xray_sync_active_users || return 1
}

bo_xray_api_port() {
  local port="${BLACKOUT_XRAY_API_PORT:-60001}" configured
  if ! declare -F bo_setting_get >/dev/null 2>&1 && [ -r "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/db.sh" ]; then
    # shellcheck disable=SC1091
    . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/db.sh"
  fi
  if declare -F bo_setting_get >/dev/null 2>&1; then
    configured="$(bo_setting_get xray_api_port 2>/dev/null || true)"
    [ -n "$configured" ] && port="$configured"
  fi
  case "$port" in
    ''|*[!0-9]*)
      printf 'invalid xray_api_port: %s\n' "$port" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$port"
}

bo_xray_api() {
  local service="$1" port
  shift
  port="$(bo_xray_api_port)" || return 1
  xray api "$service" --server=127.0.0.1:"$port" "$@"
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
