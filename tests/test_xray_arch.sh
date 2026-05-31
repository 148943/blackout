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
