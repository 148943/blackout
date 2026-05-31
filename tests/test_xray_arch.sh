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

zip="$tmpdir/Xray-linux-64.zip"
digest="$tmpdir/Xray-linux-64.zip.dgst"
printf 'xray zip payload\n' > "$zip"
sha="$(sha256sum "$zip" | awk '{print $1}')"
printf 'SHA256 (%s) = %s\n' "Xray-linux-64.zip" "$sha" > "$digest"
bo_xray_verify_zip "$zip" "$digest" "Xray-linux-64.zip"

printf 'SHA256 (%s) = %s\n' "Xray-linux-64.zip" "0000000000000000000000000000000000000000000000000000000000000000" > "$digest"
if bo_xray_verify_zip "$zip" "$digest" "Xray-linux-64.zip" >/dev/null 2>&1; then
  echo "invalid digest accepted" >&2
  exit 1
fi

bo_trace() { printf 'trace: %s\n' "$*"; }
bo_warn() { printf 'warn: %s\n' "$*" >&2; }
uname() { printf 'x86_64\n'; }
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
      sha="$(sha256sum "${output%.dgst}" | awk '{print $1}')"
      printf 'SHA256 (%s) = %s\n' "$(basename "${output%.dgst}")" "$sha" > "$output"
      ;;
    *) printf 'downloaded zip\n' > "$output" ;;
  esac
}

out="$(bo_xray_download v1.0.0 "$tmpdir/download")"
[ "$out" = "$tmpdir/download/Xray-linux-64.zip" ]
