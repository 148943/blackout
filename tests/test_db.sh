#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/lib/db.sh"

tmpdb="$(mktemp)"
trap 'rm -f "$tmpdb"' EXIT
BLACKOUT_DB="$tmpdb"
bo_db_init
bo_db_init
sqlite3 "$BLACKOUT_DB" "select name from sqlite_master where type='table' and name='users';" | grep -qx users
