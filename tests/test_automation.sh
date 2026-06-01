#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export BLACKOUT_LIB_DIR="$ROOT_DIR/lib"
export BLACKOUT_BIN_PATH="$tmp/usr/local/bin/blackout"
export BLACKOUT_EXPIRE_CRON="$tmp/etc/cron.d/blackout-expire"
export NO_COLOR=1

. "$ROOT_DIR/lib/common.sh"
. "$ROOT_DIR/lib/automation.sh"

bo_automation_expire_install
[ -f "$BLACKOUT_EXPIRE_CRON" ]
grep -q 'SHELL=/bin/sh' "$BLACKOUT_EXPIRE_CRON"
grep -q 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' "$BLACKOUT_EXPIRE_CRON"
grep -q '\*/5 \* \* \* \* root '"$BLACKOUT_BIN_PATH"' user expire >>/var/log/blackout-expire.log 2>&1' "$BLACKOUT_EXPIRE_CRON"

bo_automation_cmd expire status | grep -q 'enabled:'
bo_automation_cmd expire remove
[ ! -e "$BLACKOUT_EXPIRE_CRON" ]
bo_automation_cmd expire status | grep -q 'disabled:'

if ( bo_automation_cmd expire nope ) >/dev/null 2>&1; then
  echo "unknown expire automation command accepted" >&2
  exit 1
fi
