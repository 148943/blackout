#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/lib/time.sh"

[ "$(bo_duration_seconds 12h)" = "43200" ]
[ "$(bo_duration_seconds 7d)" = "604800" ]
[ "$(bo_duration_seconds 30d)" = "2592000" ]
[ "$(bo_duration_seconds 1m)" = "2592000" ]
[ "$(bo_expiry_epoch never)" = "4102444800" ]
if bo_duration_seconds nope >/dev/null 2>&1; then
  echo "invalid duration accepted" >&2
  exit 1
fi
