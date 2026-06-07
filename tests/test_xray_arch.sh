#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/lib/xray.sh"

[ "$(bo_xray_asset_for_arch x86_64)" = "Xray-linux-64.zip" ]
[ "$(bo_xray_asset_for_arch amd64)" = "Xray-linux-64.zip" ]
[ "$(bo_xray_asset_for_arch aarch64)" = "Xray-linux-arm64-v8a.zip" ]
[ "$(bo_xray_asset_for_arch arm64)" = "Xray-linux-arm64-v8a.zip" ]
if bo_xray_asset_for_arch mips >/dev/null 2>&1; then
  echo "unsupported arch accepted" >&2
  exit 1
fi

[ "$(bo_xray_stat_name aiman uplink)" = "user>>>aiman>>>traffic>>>uplink" ]
[ "$(bo_xray_stat_name aiman downlink)" = "user>>>aiman>>>traffic>>>downlink" ]
if bo_xray_stat_name aiman sideways >/dev/null 2>&1; then
  echo "unsupported stat direction accepted" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin="$tmpdir/bin"
mkdir -p "$bin"
cat >"$bin/xray" <<'SH'
#!/usr/bin/env bash
printf 'xray %s\n' "$*" >>"$BLACKOUT_TEST_LOG"
SH
chmod +x "$bin/xray"
export PATH="$bin:$PATH"
export BLACKOUT_TEST_LOG="$tmpdir/calls.log"

BLACKOUT_XRAY_API_PORT=61001 bo_xray_api statsquery --pattern sample
grep -q 'xray api statsquery --server=127.0.0.1:61001 --pattern sample' "$BLACKOUT_TEST_LOG"

bo_setting_get() {
  [ "$1" = xray_api_port ] && printf '62002\n'
}
bo_xray_api statsquery --pattern configured
grep -q 'xray api statsquery --server=127.0.0.1:62002 --pattern configured' "$BLACKOUT_TEST_LOG"

bo_trace() { printf 'trace: %s\n' "$*"; }
bo_warn() { printf 'warn: %s\n' "$*" >&2; }

zip="$tmpdir/Xray-linux-64.zip"
digest="$tmpdir/Xray-linux-64.zip.dgst"
printf 'xray zip payload\n' > "$zip"
sha="$(sha256sum "$zip" | awk '{print $1}')"
printf 'SHA2-256= %s\n' "$sha" > "$digest"
bo_xray_verify_zip "$zip" "$digest" "Xray-linux-64.zip"

printf 'SHA256 (%s) = %s\n' "Xray-linux-64.zip" "0000000000000000000000000000000000000000000000000000000000000000" > "$digest"
if bo_xray_verify_zip "$zip" "$digest" "Xray-linux-64.zip" >/dev/null 2>&1; then
  echo "invalid digest accepted" >&2
  exit 1
fi

printf 'no checksum here\n' > "$digest"
if bo_xray_verify_zip "$zip" "$digest" "Xray-linux-64.zip" >/dev/null 2>&1; then
  echo "missing digest accepted" >&2
  exit 1
fi

uname() { printf 'x86_64\n'; }
curl() {
  local output="" arg next_is_output=0
  if [ "$*" = "-fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest" ]; then
    printf '{"tag_name":"v9.9.9"}\n'
    return 0
  fi
  for arg in "$@"; do
    if [ "$next_is_output" -eq 1 ]; then
      output="$arg"
      next_is_output=0
      continue
    fi
    [ "$arg" = "-o" ] && next_is_output=1
  done
  [ -n "$output" ] || return 1
  case "$output" in
    *.dgst)
      sha="$(sha256sum "${output%.dgst}" | awk '{print $1}')"
      printf 'SHA2-256= %s\n' "$sha" > "$output"
      printf '200'
      ;;
    *) printf 'downloaded zip\n' > "$output" ;;
  esac
}

latest_err="$tmpdir/latest-download.err"
out="$(bo_xray_download latest "$tmpdir/download-latest" 2>"$latest_err")"
[ "$out" = "$tmpdir/download-latest/Xray-linux-64.zip" ]
grep -q 'download: https://github.com/XTLS/Xray-core/releases/download/v9.9.9/Xray-linux-64.zip' "$latest_err"
if grep -q '/releases/download/latest/' "$latest_err"; then
  echo "latest was not resolved before download" >&2
  exit 1
fi

curl() {
  if [ "$*" = "-fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest" ]; then
    printf '{"tag_name":"latest"}\n'
    return 0
  fi
  echo "resolver failure should stop before asset download" >&2
  return 1
}
download_status=0
download_out="$(bo_xray_download latest "$tmpdir/download-bad-latest" 2>"$tmpdir/bad-latest.err")" || download_status=$?
[ "$download_status" -ne 0 ]
[ -z "$download_out" ]
grep -q 'failed to resolve latest Xray version' "$tmpdir/bad-latest.err"
if grep -q '/releases/download/latest/' "$tmpdir/bad-latest.err"; then
  echo "bad latest resolver reached asset download" >&2
  exit 1
fi

curl() {
  local output="" arg next_is_output=0
  if [ "$*" = "-fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest" ]; then
    printf '{"tag_name":"v9.9.9"}\n'
    return 0
  fi
  for arg in "$@"; do
    if [ "$next_is_output" -eq 1 ]; then
      output="$arg"
      next_is_output=0
      continue
    fi
    [ "$arg" = "-o" ] && next_is_output=1
  done
  [ -n "$output" ] || return 1
  case "$output" in
    *.dgst)
      sha="$(sha256sum "${output%.dgst}" | awk '{print $1}')"
      printf 'SHA2-256= %s\n' "$sha" > "$output"
      printf '200'
      ;;
    *) printf 'downloaded zip\n' > "$output" ;;
  esac
}

out="$(bo_xray_download v1.0.0 "$tmpdir/download")"
[ "$out" = "$tmpdir/download/Xray-linux-64.zip" ]

curl() {
  local output="" arg next_is_output=0
  for arg in "$@"; do
    if [ "$next_is_output" -eq 1 ]; then
      output="$arg"
      next_is_output=0
      continue
    fi
    [ "$arg" = "-o" ] && next_is_output=1
  done
  [ -n "$output" ] || return 1
  case "$output" in
    *.dgst) printf '404' ;;
    *) printf 'downloaded zip\n' > "$output" ;;
  esac
}

out="$(bo_xray_download v1.0.0 "$tmpdir/download-404" 2>/dev/null)"
[ "$out" = "$tmpdir/download-404/Xray-linux-64.zip" ]

curl() {
  local output="" arg next_is_output=0
  for arg in "$@"; do
    if [ "$next_is_output" -eq 1 ]; then
      output="$arg"
      next_is_output=0
      continue
    fi
    [ "$arg" = "-o" ] && next_is_output=1
  done
  [ -n "$output" ] || return 1
  case "$output" in
    *.dgst) printf '404' ;;
    *)
      printf 'curl: (22) The requested URL returned error: 404\n' >&2
      return 22
      ;;
  esac
}

download_status=0
download_err="$tmpdir/download-zip-404.err"
download_out="$(bo_xray_download 9812312.1 "$tmpdir/download-zip-404" 2>"$download_err")" || download_status=$?
[ "$download_status" -ne 0 ]
[ -z "$download_out" ]
grep -q 'failed to download Xray asset: Xray-linux-64.zip for 9812312.1' "$download_err"
[ ! -e "$tmpdir/download-zip-404/Xray-linux-64.zip" ]

curl() {
  local output="" arg next_is_output=0
  for arg in "$@"; do
    if [ "$next_is_output" -eq 1 ]; then
      output="$arg"
      next_is_output=0
      continue
    fi
    [ "$arg" = "-o" ] && next_is_output=1
  done
  [ -n "$output" ] || return 1
  case "$output" in
    *.dgst) printf '500' ;;
    *) printf 'downloaded zip\n' > "$output" ;;
  esac
}

download_status=0
download_out="$(bo_xray_download v1.0.0 "$tmpdir/download-500" 2>/dev/null)" || download_status=$?
[ "$download_status" -ne 0 ]
[ -z "$download_out" ]

curl() {
  local output="" arg next_is_output=0
  for arg in "$@"; do
    if [ "$next_is_output" -eq 1 ]; then
      output="$arg"
      next_is_output=0
      continue
    fi
    [ "$arg" = "-o" ] && next_is_output=1
  done
  [ -n "$output" ] || return 1
  case "$output" in
    *.dgst) return 7 ;;
    *) printf 'downloaded zip\n' > "$output" ;;
  esac
}

download_status=0
download_out="$(bo_xray_download v1.0.0 "$tmpdir/download-network" 2>/dev/null)" || download_status=$?
[ "$download_status" -ne 0 ]
[ -z "$download_out" ]

curl() {
  local output="" arg next_is_output=0
  for arg in "$@"; do
    if [ "$next_is_output" -eq 1 ]; then
      output="$arg"
      next_is_output=0
      continue
    fi
    [ "$arg" = "-o" ] && next_is_output=1
  done
  [ -n "$output" ] || return 1
  case "$output" in
    *.dgst)
      printf 'SHA2-256= %064d\n' 0 > "$output"
      printf '200'
      ;;
    *) printf 'downloaded zip\n' > "$output" ;;
  esac
}

download_status=0
download_out="$(bo_xray_download v1.0.0 "$tmpdir/download-fail" 2>/dev/null)" || download_status=$?
[ "$download_status" -ne 0 ]
[ -z "$download_out" ]

install_log="$tmpdir/install.log"
bo_need_root() {
  :
}
id() {
  if [ "${1:-}" = "-u" ]; then
    printf '0\n'
  else
    command id "$@"
  fi
}
systemctl() {
  printf 'systemctl %s\n' "$*" >>"$install_log"
}
unzip() {
  local zip="" dest="" next_dest=0 arg
  for arg in "$@"; do
    if [ "$next_dest" -eq 1 ]; then
      dest="$arg"
      next_dest=0
      continue
    fi
    case "$arg" in
      -d) next_dest=1 ;;
      -*) ;;
      *) zip="$arg" ;;
    esac
  done
  python3 - "$zip" "$dest" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    archive.extractall(sys.argv[2])
PY
}
install() {
  local args=("$@") dest="${@: -1}"
  case "$dest" in
    /usr/local/bin/xray) args[$(($# - 1))]="$tmpdir/usr/local/bin/xray" ;;
    /usr/local/share/xray/geoip.dat) args[$(($# - 1))]="$tmpdir/usr/local/share/xray/geoip.dat" ;;
    /usr/local/share/xray/geosite.dat) args[$(($# - 1))]="$tmpdir/usr/local/share/xray/geosite.dat" ;;
  esac
  command install "${args[@]}"
}
bo_xray_download() {
  local zip="$2/Xray-linux-64.zip"
  python3 - "$zip" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("xray", "binary\n")
    archive.writestr("geoip.dat", "geoip\n")
PY
  printf '%s\n' "$zip"
}
sync_calls=0
bo_user_sync_active_to_xray() {
  sync_calls=$((sync_calls + 1))
}
bo_xray_install_version v9.9.9
grep -q 'systemctl restart xray' "$install_log"
[ "$sync_calls" -eq 1 ]

BLACKOUT_XRAY_NO_RESTART=1
bo_test_xray_install_wrapper() {
  bo_xray_install_version v9.9.9
}
bo_test_xray_install_wrapper
unset BLACKOUT_XRAY_NO_RESTART

bo_user_sync_active_to_xray() {
  return 37
}
if bo_xray_install_version v9.9.10 >/dev/null 2>&1; then
  echo "xray install succeeded despite replay failure" >&2
  exit 1
fi
